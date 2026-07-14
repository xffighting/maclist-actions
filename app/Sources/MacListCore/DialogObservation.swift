import CoreGraphics
import Foundation

public struct DialogStructureSnapshot: Equatable, Sendable {
    public let role: String
    public let hasFileContainer: Bool
    public let hasOKButton: Bool
    public let hasCancelButton: Bool
    public let hasFileURLSemantics: Bool
    public let hasPathSemantics: Bool
    public let isModal: Bool
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isHidden: Bool
    public let defaultButtonTitle: String?

    public init(
        role: String,
        hasFileContainer: Bool,
        hasOKButton: Bool,
        hasCancelButton: Bool,
        hasFileURLSemantics: Bool = false,
        hasPathSemantics: Bool = false,
        isModal: Bool = false,
        isFocused: Bool = false,
        isMinimized: Bool = false,
        isHidden: Bool = false,
        defaultButtonTitle: String? = nil
    ) {
        self.role = role
        self.hasFileContainer = hasFileContainer
        self.hasOKButton = hasOKButton
        self.hasCancelButton = hasCancelButton
        self.hasFileURLSemantics = hasFileURLSemantics
        self.hasPathSemantics = hasPathSemantics
        self.isModal = isModal
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.defaultButtonTitle = defaultButtonTitle
    }
}

public enum DialogKind: String, Equatable, Sendable {
    case openFile
    case save
    case folder
    case unknown
}

public enum DialogClassifier {
    public static func isSupportedFileDialog(_ snapshot: DialogStructureSnapshot) -> Bool {
        confidence(for: snapshot) >= 9
    }

    public static func confidence(for snapshot: DialogStructureSnapshot) -> Int {
        guard snapshot.role == "AXWindow" || snapshot.role == "AXSheet",
              !snapshot.isMinimized,
              !snapshot.isHidden,
              snapshot.hasFileContainer,
              snapshot.hasOKButton,
              snapshot.hasFileURLSemantics || snapshot.hasPathSemantics else {
            return 0
        }

        var score = snapshot.role == "AXSheet" ? 2 : 1
        score += 3
        score += 2
        if snapshot.hasCancelButton { score += 1 }
        if snapshot.hasFileURLSemantics { score += 3 }
        if snapshot.hasPathSemantics { score += 2 }
        if snapshot.isModal { score += 1 }
        if snapshot.isFocused { score += 2 }
        return score
    }

    public static func kind(
        defaultButtonTitle: String?,
        defaultButtonIdentifier: String? = nil,
        dialogContextText: String? = nil,
        hasSaveFilenameField: Bool = false
    ) -> DialogKind {
        let buttonTitle = defaultButtonTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let identifier = defaultButtonIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let context = dialogContextText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let folderTokens = [
            "folder", "choose a folder", "select a folder",
            "文件夹", "檔案夾", "資料夾"
        ]
        let canonicalOpenTokens = ["open", "打开", "開啟"]
        let fileActionTokens = [
            "attach", "upload", "choose a file", "select a file",
            "上传", "上傳", "附件", "选择文件", "選擇檔案"
        ]
        let saveTokens = ["save", "保存", "存储", "儲存"]

        if folderTokens.contains(where: buttonTitle.contains) {
            return .folder
        }
        if (canonicalOpenTokens + fileActionTokens).contains(
            where: buttonTitle.contains
        ) {
            return .openFile
        }
        if saveTokens.contains(where: buttonTitle.contains) {
            return .save
        }
        if identifier.contains("folder") || identifier.contains("directory") {
            return .folder
        }
        if ["open", "attach", "upload", "choosefile", "selectfile"].contains(
            where: identifier.contains
        ) {
            return .openFile
        }
        if identifier.contains("save") {
            return .save
        }
        if hasSaveFilenameField {
            return .save
        }
        let contextHasFolder = folderTokens.contains(where: context.contains)
        let contextHasOpen = (canonicalOpenTokens + fileActionTokens).contains(
            where: context.contains
        )
        let contextHasSave = saveTokens.contains(where: context.contains)
        if contextHasFolder, !contextHasOpen, !contextHasSave {
            return .folder
        }
        if contextHasOpen, !contextHasSave {
            return .openFile
        }
        if contextHasSave, !contextHasOpen {
            return .save
        }
        return .unknown
    }

    public static func canAutomaticallyAttach(kind: DialogKind) -> Bool {
        kind == .openFile
    }
}

public struct ObservedDialog: Equatable, Sendable {
    public let id: String
    public let pid: Int32
    public let frame: CGRect
    public let confidence: Int
    public let isFocused: Bool
    public let isVisible: Bool

    public init(
        id: String,
        pid: Int32,
        frame: CGRect,
        confidence: Int = 100,
        isFocused: Bool = true,
        isVisible: Bool = true
    ) {
        self.id = id
        self.pid = pid
        self.frame = frame
        self.confidence = confidence
        self.isFocused = isFocused
        self.isVisible = isVisible
    }
}

public enum DialogProcessCandidatePlanner {
    public static func ordered(
        ownPID: Int32,
        hostPID: Int32?,
        focusedPID: Int32?,
        attachedPID: Int32?,
        servicePIDs: [Int32],
        visibleWindowPIDs: [Int32]
    ) -> [Int32] {
        var result: [Int32] = []
        var seen = Set<Int32>()

        func append(_ pid: Int32?) {
            guard let pid, pid > 0, pid != ownPID, seen.insert(pid).inserted else {
                return
            }
            result.append(pid)
        }

        append(attachedPID)
        append(focusedPID)
        servicePIDs.forEach { append($0) }
        append(hostPID)
        visibleWindowPIDs.forEach { append($0) }
        return result
    }
}

public struct DialogInteractionToken: Equatable, Sendable {
    public let dialogID: String
    public let generation: UInt64

    public init(dialogID: String, generation: UInt64) {
        self.dialogID = dialogID
        self.generation = generation
    }
}

public struct DialogInteractionState: Equatable, Sendable {
    public private(set) var currentDialogID: String?
    public private(set) var generation: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func attach(dialogID: String) -> Bool {
        guard currentDialogID != dialogID else { return false }
        generation &+= 1
        currentDialogID = dialogID
        return true
    }

    public mutating func detach() {
        guard currentDialogID != nil else { return }
        generation &+= 1
        currentDialogID = nil
    }

    public var token: DialogInteractionToken? {
        currentDialogID.map {
            DialogInteractionToken(dialogID: $0, generation: generation)
        }
    }

    public func isCurrent(_ token: DialogInteractionToken) -> Bool {
        token.dialogID == currentDialogID && token.generation == generation
    }
}

public enum DialogAttachmentFocusPolicy {
    public static func shouldAttach(
        dialogPID: Int32,
        hostPID: Int32,
        dialogTopLevelID: Int,
        dialogIsLocallyFocused: Bool,
        isOnlyCandidateInProcess: Bool,
        systemFocusedPID: Int32?,
        systemFocusedTopLevelID: Int?,
        hasTopVisibleWindowEvidence: Bool
    ) -> Bool {
        guard let systemFocusedPID else { return false }
        let exactTopLevel = systemFocusedTopLevelID == dialogTopLevelID

        if systemFocusedPID == dialogPID {
            return exactTopLevel
                || (dialogIsLocallyFocused && isOnlyCandidateInProcess)
        }
        if dialogPID != hostPID, systemFocusedPID == hostPID {
            return exactTopLevel || hasTopVisibleWindowEvidence
        }
        return false
    }

    public static func shouldKeepAttached(
        dialogPID: Int32,
        hostPID: Int32,
        dialogTopLevelID: Int,
        dialogIsLocallyFocused: Bool,
        systemFocusedPID: Int32?,
        systemFocusedTopLevelID: Int?,
        ownPID: Int32,
        ownPanelIsKey: Bool,
        focusUnavailableWithinGrace: Bool,
        hasTopVisibleWindowEvidence: Bool
    ) -> Bool {
        if systemFocusedPID == nil { return focusUnavailableWithinGrace }
        if systemFocusedPID == ownPID { return ownPanelIsKey }
        return shouldAttach(
            dialogPID: dialogPID,
            hostPID: hostPID,
            dialogTopLevelID: dialogTopLevelID,
            dialogIsLocallyFocused: dialogIsLocallyFocused,
            isOnlyCandidateInProcess: true,
            systemFocusedPID: systemFocusedPID,
            systemFocusedTopLevelID: systemFocusedTopLevelID,
            hasTopVisibleWindowEvidence: hasTopVisibleWindowEvidence
        )
    }
}

public enum DialogWindowGeometry {
    public static func isLikelySameWindow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else {
            return false
        }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let intersectionArea = intersection.width * intersection.height
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        return smallerArea > 0 && intersectionArea / smallerArea >= 0.72
    }
}

public struct DialogVisibleWindowEvidence: Equatable, Sendable {
    public let pid: Int32
    public let frame: CGRect
    public let rank: Int

    public init(pid: Int32, frame: CGRect, rank: Int) {
        self.pid = pid
        self.frame = frame
        self.rank = rank
    }
}

public enum DialogVisibleStackPolicy {
    public static func isBoundToHost(
        dialogPID: Int32,
        hostPID: Int32,
        dialogFrame: CGRect,
        confidence: Int,
        windows: [DialogVisibleWindowEvidence]
    ) -> Bool {
        guard confidence >= 11,
              let panelWindow = windows.first(where: { window in
                window.pid == dialogPID
                    && DialogWindowGeometry.isLikelySameWindow(
                        dialogFrame,
                        window.frame
                    )
              }) else {
            return false
        }
        let allWindowsAboveBelongToDialog = windows
            .filter { $0.rank < panelWindow.rank }
            .allSatisfy { $0.pid == dialogPID }
        guard allWindowsAboveBelongToDialog else { return false }

        let firstDifferentOwnerBelow = windows.first { window in
            window.rank > panelWindow.rank && window.pid != dialogPID
        }
        return firstDifferentOwnerBelow?.pid == hostPID
    }
}

public enum DialogObservationEvent: Equatable, Sendable {
    case permissionChanged(Bool)
    case frontmostApplicationChanged(Int32?)
    case scanCompleted([ObservedDialog])
    case dialogClosed(String)
}

public enum DialogObservationCommand: Equatable, Sendable {
    case observeApplication(Int32)
    case stopObserving
    case attach(ObservedDialog)
    case updateAttachment(ObservedDialog)
    case detach
}

public struct DialogObservationStateMachine: Sendable {
    public private(set) var permissionGranted = false
    public private(set) var observedApplicationPID: Int32?
    public private(set) var attachedDialog: ObservedDialog?

    public init() {}

    public mutating func handle(
        _ event: DialogObservationEvent
    ) -> [DialogObservationCommand] {
        switch event {
        case let .permissionChanged(granted):
            guard permissionGranted != granted else { return [] }
            permissionGranted = granted
            if granted {
                if let observedApplicationPID {
                    return [.observeApplication(observedApplicationPID)]
                }
                return []
            }

            var commands: [DialogObservationCommand] = []
            if attachedDialog != nil {
                attachedDialog = nil
                commands.append(.detach)
            }
            if observedApplicationPID != nil {
                observedApplicationPID = nil
                commands.append(.stopObserving)
            }
            return commands

        case let .frontmostApplicationChanged(pid):
            guard permissionGranted else {
                observedApplicationPID = pid
                return []
            }
            guard observedApplicationPID != pid else { return [] }

            var commands: [DialogObservationCommand] = []
            if attachedDialog != nil {
                attachedDialog = nil
                commands.append(.detach)
            }
            if observedApplicationPID != nil {
                commands.append(.stopObserving)
            }
            observedApplicationPID = pid
            if let pid {
                commands.append(.observeApplication(pid))
            }
            return commands

        case let .scanCompleted(dialogs):
            guard permissionGranted, observedApplicationPID != nil else { return [] }
            let visibleDialogs = dialogs.filter(\.isVisible)
            let next = attachedDialog.flatMap { current in
                visibleDialogs.first(where: { $0.id == current.id })
            } ?? visibleDialogs.max { lhs, rhs in
                if lhs.isFocused != rhs.isFocused {
                    return !lhs.isFocused && rhs.isFocused
                }
                return lhs.confidence < rhs.confidence
            }
            guard let next else {
                guard attachedDialog != nil else { return [] }
                attachedDialog = nil
                return [.detach]
            }

            guard let current = attachedDialog else {
                attachedDialog = next
                return [.attach(next)]
            }
            if current.id != next.id {
                attachedDialog = next
                return [.detach, .attach(next)]
            }
            if current.frame != next.frame {
                attachedDialog = next
                return [.updateAttachment(next)]
            }
            return []

        case let .dialogClosed(id):
            guard attachedDialog?.id == id else { return [] }
            attachedDialog = nil
            return [.detach]
        }
    }
}

public enum AttachedPanelLayout {
    public static func canAttach(to dialogFrame: CGRect) -> Bool {
        dialogFrame.width >= 200 && dialogFrame.height >= 160
    }

    public static func frame(
        dialogFrame: CGRect,
        visibleScreenFrame: CGRect,
        expanded: Bool
    ) -> CGRect {
        let horizontalInset: CGFloat = 16
        let preferredWidth: CGFloat = 720
        let collapsedHeight: CGFloat = 62

        let usableFrame = dialogFrame.intersection(visibleScreenFrame.insetBy(dx: 8, dy: 8))
        let anchorFrame = usableFrame.isNull || usableFrame.isEmpty ? dialogFrame : usableFrame
        let width = max(
            1,
            min(preferredWidth, anchorFrame.width - horizontalInset * 2)
        )
        let availableHeight = max(collapsedHeight, anchorFrame.height - 50)
        let height = expanded ? min(340, availableHeight) : collapsedHeight

        let top = min(anchorFrame.maxY - 8, visibleScreenFrame.maxY - 8)
        var originX = anchorFrame.midX - width / 2
        var originY = top - height

        originX = min(
            max(originX, visibleScreenFrame.minX + 8),
            visibleScreenFrame.maxX - width - 8
        )
        originY = min(
            max(originY, visibleScreenFrame.minY + 8),
            visibleScreenFrame.maxY - height - 8
        )

        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

public enum AXFrameCoordinateConverter {
    public static func appKitFrame(
        fromAXFrame frame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
