import ApplicationServices
import CoreGraphics
import MacListCore

struct DetectedFileDialog {
    let observed: ObservedDialog
    let session: FileDialogSession
    let rawFrame: CGRect
}

final class FileDialogDetector {
    private let inspector: AXFileDialogInspector

    init(inspector: AXFileDialogInspector = AXFileDialogInspector()) {
        self.inspector = inspector
    }

    func detectAll(
        in applicationPID: pid_t,
        hostApplicationPID: pid_t? = nil,
        hostApplicationName: String? = nil
    ) -> [DetectedFileDialog] {
        guard applicationPID > 0 else { return [] }

        let application = AXUIElementCreateApplication(applicationPID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let focused = AXAccess.element(application, kAXFocusedUIElementAttribute)
        let windows = AXAccess.elements(application, kAXWindowsAttribute)
        var candidates: [AXUIElement] = []

        for window in windows {
            let directSheets = AXAccess.elements(window, kAXChildrenAttribute).filter { element in
                AXAccess.string(element, kAXRoleAttribute) == kAXSheetRole as String
            }
            candidates.append(contentsOf: directSheets)
            if directSheets.isEmpty {
                candidates.append(contentsOf: AXAccess.descendants(of: window, maxNodes: 220).filter {
                    AXAccess.string($0, kAXRoleAttribute) == kAXSheetRole as String
                })
            }
        }

        if let focused,
           let topLevel = AXAccess.topLevelElement(for: focused) {
            candidates.append(topLevel)
        }

        candidates.append(contentsOf: windows.filter { window in
            let role = AXAccess.string(window, kAXRoleAttribute)
            let subrole = AXAccess.string(window, kAXSubroleAttribute)
            let modal = AXAccess.bool(window, kAXModalAttribute) ?? false
            return role == kAXSheetRole as String
                || subrole == kAXDialogSubrole as String
                || modal
        })

        var seen = Set<CFHashCode>()
        let hostName = hostApplicationName ?? "当前应用"
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

        return candidates.compactMap { candidate in
            let hash = CFHash(candidate)
            guard seen.insert(hash).inserted,
                  let inspection = inspector.inspect(
                    candidate,
                    focusedElement: focused
                  ),
                  DialogClassifier.isSupportedFileDialog(inspection.snapshot),
                  DialogClassifier.canAutomaticallyAttach(kind: inspection.kind),
                  let rawFrame = AXAccess.rawFrame(candidate),
                  AttachedPanelLayout.canAttach(
                    to: CGRect(origin: .zero, size: rawFrame.size)
                  ) else {
                return nil
            }

            var dialogPID: pid_t = applicationPID
            _ = AXUIElementGetPid(candidate, &dialogPID)
            let frame = AXFrameCoordinateConverter.appKitFrame(
                fromAXFrame: rawFrame,
                primaryScreenHeight: primaryHeight
            )
            let id = "\(dialogPID):\(hash)"
            let session = FileDialogSession(
                id: id,
                hostPID: hostApplicationPID ?? applicationPID,
                dialogOwnerPID: dialogPID,
                originalWindow: candidate,
                originalFocusedElement: focused ?? candidate,
                hostApplicationName: hostName,
                dialogKind: inspection.kind,
                originalWindowRole: inspection.snapshot.role,
                originalAuthoritativeDefaultButton: inspection.authoritativeDefaultButton
            )
            return DetectedFileDialog(
                observed: ObservedDialog(
                    id: id,
                    pid: Int32(dialogPID),
                    frame: frame,
                    confidence: inspection.confidence,
                    isFocused: inspection.snapshot.isFocused,
                    isVisible: !inspection.snapshot.isMinimized && !inspection.snapshot.isHidden
                ),
                session: session,
                rawFrame: rawFrame
            )
        }
    }
}
