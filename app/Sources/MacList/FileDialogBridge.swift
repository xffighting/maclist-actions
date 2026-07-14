import AppKit
import ApplicationServices
import Carbon
import MacListCore

final class FileDialogSession {
    let id: String
    let hostPID: pid_t
    let dialogOwnerPID: pid_t
    let originalWindow: AXUIElement
    let originalFocusedElement: AXUIElement
    let hostApplicationName: String
    let dialogKind: DialogKind

    init(
        id: String,
        hostPID: pid_t,
        dialogOwnerPID: pid_t,
        originalWindow: AXUIElement,
        originalFocusedElement: AXUIElement,
        hostApplicationName: String,
        dialogKind: DialogKind
    ) {
        self.id = id
        self.hostPID = hostPID
        self.dialogOwnerPID = dialogOwnerPID
        self.originalWindow = originalWindow
        self.originalFocusedElement = originalFocusedElement
        self.hostApplicationName = hostApplicationName
        self.dialogKind = dialogKind
    }
}

final class FileDialogSelectionOperation {
    private let lock = NSLock()
    private var finished = false
    private var cancelHandler: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func installCancelHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        cancelHandler = handler
        lock.unlock()
    }

    func cancel() {
        let handler: (() -> Void)?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        cancelled = true
        finished = true
        handler = cancelHandler
        cancelHandler = nil
        lock.unlock()
        handler?()
    }

    fileprivate func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        cancelHandler = nil
        return true
    }
}

final class FileDialogBridge {
    typealias Completion = (Result<Void, DialogSelectionError>) -> Void

    private let inspector: AXFileDialogInspector
    private let queue = DispatchQueue(
        label: "app.maclist.dialog-bridge",
        qos: .userInitiated
    )

    init(inspector: AXFileDialogInspector = AXFileDialogInspector()) {
        self.inspector = inspector
    }

    @discardableResult
    func selectFile(
        _ url: URL,
        in session: FileDialogSession,
        mode: DialogSelectionMode,
        completion: @escaping Completion
    ) -> FileDialogSelectionOperation {
        let operation = FileDialogSelectionOperation()
        operation.installCancelHandler {
            DispatchQueue.main.async {
                completion(.failure(.operationCancelled))
            }
        }
        let complete: Completion = { result in
            guard operation.finish() else { return }
            DispatchQueue.main.async {
                completion(result)
            }
        }

        let target: ValidatedFile
        do {
            target = try DialogSelectionPolicy.validateFile(url)
        } catch let error as DialogSelectionError {
            complete(.failure(error))
            return operation
        } catch {
            complete(.failure(.systemFailure(error.localizedDescription)))
            return operation
        }

        guard AccessibilityPermission.isTrusted(promptIfNeeded: false) else {
            complete(.failure(.accessibilityPermissionRequired))
            return operation
        }
        guard AccessibilityPermission.canPostEvents(promptIfNeeded: false) else {
            complete(.failure(.postEventPermissionRequired))
            return operation
        }
        guard mode == .selectOnly else {
            complete(.failure(.unsupportedDialog))
            return operation
        }

        queue.async { [weak self] in
            guard let self, !operation.isCancelled else { return }
            guard self.liveInspection(for: session) != nil else {
                complete(.failure(.noFileDialog))
                return
            }
            let existingSheetIDs = self.sheetIDs(in: session.originalWindow)
            self.poll(
                timeout: 0.8,
                interval: 0.04,
                step: .restoreDialogFocus,
                operation: operation,
                condition: {
                    self.focusedEventTargetPID(for: session) != nil
                }
            ) { focusResult in
                guard !operation.isCancelled else { return }
                switch focusResult {
                case let .failure(error):
                    complete(.failure(error))
                case .success:
                    guard let eventTargetPID = self.focusedEventTargetPID(for: session),
                          self.postGoToFolderShortcut(
                            to: eventTargetPID,
                            session: session,
                            operation: operation
                          ) else {
                        complete(.failure(.systemFailure("无法安全地把快捷键交给原文件窗口")))
                        return
                    }
                    Diagnostics.log("go_to_folder_shortcut_posted")
                    self.awaitGoToFolder(
                        target,
                        session: session,
                        mode: mode,
                        existingSheetIDs: existingSheetIDs,
                        operation: operation,
                        completion: complete
                    )
                }
            }
        }
        return operation
    }

    private func awaitGoToFolder(
        _ target: ValidatedFile,
        session: FileDialogSession,
        mode: DialogSelectionMode,
        existingSheetIDs: Set<CFHashCode>,
        operation: FileDialogSelectionOperation,
        completion: @escaping Completion
    ) {
        poll(
            timeout: 1.4,
            interval: 0.05,
            step: .locateWritablePathField,
            operation: operation,
            condition: {
                self.goToFolderContext(
                    in: session,
                    excluding: existingSheetIDs
                ) != nil
            }
        ) { result in
            guard !operation.isCancelled else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                guard let context = self.goToFolderContext(
                    in: session,
                    excluding: existingSheetIDs
                ) else {
                    completion(.failure(.bridgeTimedOut(.locateWritablePathField)))
                    return
                }
                self.writePathAndContinue(
                    target,
                    context: context,
                    session: session,
                    mode: mode,
                    existingSheetIDs: existingSheetIDs,
                    operation: operation,
                    completion: completion
                )
            }
        }
    }

    private struct GoToFolderContext {
        let id: CFHashCode
        let sheet: AXUIElement
        let pathField: AXUIElement
        let defaultButton: AXUIElement
    }

    private func goToFolderContext(
        in session: FileDialogSession,
        excluding existingSheetIDs: Set<CFHashCode>
    ) -> GoToFolderContext? {
        guard let focused = focusedElement(for: session)?.element,
              let sheet = AXAccess.nearestAncestor(
                from: focused,
                matching: [kAXSheetRole as String]
              ),
              !existingSheetIDs.contains(CFHash(sheet)),
              AXAccess.isAncestor(session.originalWindow, of: sheet) else {
            return nil
        }

        let candidates = [focused] + AXAccess.descendants(of: sheet, maxNodes: 120)
        let writableFields = uniqueElements(candidates.filter(isWritablePathField))
        let secureFields = candidates.filter { element in
            AXAccess.string(element, kAXSubroleAttribute)
                == kAXSecureTextFieldSubrole as String
        }
        guard isWritablePathField(focused),
              writableFields.count == 1,
              secureFields.isEmpty else {
            return nil
        }

        guard let defaultButton = AXAccess.element(sheet, kAXDefaultButtonAttribute),
              AXAccess.isAncestor(sheet, of: defaultButton),
              isGoButton(defaultButton) else {
            return nil
        }
        [sheet, focused, defaultButton].forEach {
            AXUIElementSetMessagingTimeout($0, 0.20)
        }
        return GoToFolderContext(
            id: CFHash(sheet),
            sheet: sheet,
            pathField: focused,
            defaultButton: defaultButton
        )
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen = Set<CFHashCode>()
        return elements.filter { seen.insert(CFHash($0)).inserted }
    }

    private func isGoButton(_ button: AXUIElement) -> Bool {
        guard let title = AXAccess.string(button, kAXTitleAttribute)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return ["go", "前往", "移至", "移動"].contains { token in
            title == token || title.contains("\(token) ")
        }
    }

    private func isWritablePathField(_ element: AXUIElement) -> Bool {
        AXAccess.string(element, kAXRoleAttribute) == kAXTextFieldRole as String
            && AXAccess.string(element, kAXSubroleAttribute)
                != kAXSecureTextFieldSubrole as String
            && AXAccess.isSettable(element, kAXValueAttribute)
    }

    private func writePathAndContinue(
        _ target: ValidatedFile,
        context: GoToFolderContext,
        session: FileDialogSession,
        mode: DialogSelectionMode,
        existingSheetIDs: Set<CFHashCode>,
        operation: FileDialogSelectionOperation,
        completion: @escaping Completion
    ) {
        guard canContinue(
            operation,
            session: session,
            goToContext: context
        ) else {
            completion(.failure(.operationCancelled))
            return
        }
        let setStatus = AXAccess.setValue(
            target.url.path as CFString,
            on: context.pathField,
            attribute: kAXValueAttribute
        )
        guard setStatus == .success,
              canContinue(operation, session: session, goToContext: context),
              AXAccess.string(context.pathField, kAXValueAttribute) == target.url.path else {
            completion(.failure(.systemFailure("无法写入并核对绝对路径")))
            return
        }

        guard canContinue(operation, session: session, goToContext: context),
              AXAccess.bool(context.defaultButton, kAXEnabledAttribute) != false,
              AXAccess.supportsPress(context.defaultButton),
              canContinue(operation, session: session, goToContext: context),
              AXAccess.press(context.defaultButton) == .success else {
            completion(.failure(.systemFailure("无法确认“前往文件夹”路径")))
            return
        }

        var consecutiveClosedChecks = 0
        poll(
            timeout: 1.0,
            interval: 0.06,
            step: .confirmPath,
            operation: operation,
            condition: {
                if self.isGoToFolderContextLive(context, in: session) {
                    consecutiveClosedChecks = 0
                    return false
                }
                consecutiveClosedChecks += 1
                return consecutiveClosedChecks >= 2
            }
        ) { navigationResult in
            guard !operation.isCancelled else { return }
            switch navigationResult {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                guard let inspection = self.liveInspection(for: session) else {
                    completion(.failure(.noFileDialog))
                    return
                }
                self.verifySelectionAndFinish(
                    target,
                    session: session,
                    mode: mode,
                    fileContainers: inspection.fileContainers,
                    operation: operation,
                    completion: completion
                )
            }
        }
    }

    private func verifySelectionAndFinish(
        _ target: ValidatedFile,
        session: FileDialogSession,
        mode: DialogSelectionMode,
        fileContainers: [AXUIElement],
        operation: FileDialogSelectionOperation,
        completion: @escaping Completion
    ) {
        var currentContainers = fileContainers
        var lastContainerRefresh = Date.distantPast
        poll(
            timeout: 2.2,
            interval: 0.10,
            step: .verifyExactSelection,
            operation: operation,
            condition: {
                if self.isExactlySelected(target, in: currentContainers) {
                    return true
                }
                if Date().timeIntervalSince(lastContainerRefresh) >= 0.35,
                   let inspection = self.liveInspection(for: session) {
                    currentContainers = inspection.fileContainers
                    lastContainerRefresh = Date()
                    return self.isExactlySelected(target, in: currentContainers)
                }
                return false
            }
        ) { result in
            guard !operation.isCancelled else { return }
            switch result {
            case .failure:
                completion(.failure(.selectionCouldNotBeVerified(target.url.path)))
            case .success:
                guard let finalInspection = self.liveInspection(for: session),
                      self.isExactlySelected(
                        target,
                        in: finalInspection.fileContainers
                      ) else {
                    completion(.failure(.selectionCouldNotBeVerified(target.url.path)))
                    return
                }
                guard mode == .selectOnly else {
                    completion(.failure(.unsupportedDialog))
                    return
                }
                completion(.success(()))
            }
        }
    }

    private func isExactlySelected(
        _ target: ValidatedFile,
        in fileContainers: [AXUIElement]
    ) -> Bool {
        for container in fileContainers {
            AXUIElementSetMessagingTimeout(container, 0.15)
            let selectionRoots = [container]
                + AXAccess.descendants(of: container, maxNodes: 80)
            let selected = selectionRoots.flatMap { selectionRoot in
                AXUIElementSetMessagingTimeout(selectionRoot, 0.12)
                return AXAccess.elements(selectionRoot, kAXSelectedChildrenAttribute)
                    + AXAccess.elements(selectionRoot, kAXSelectedRowsAttribute)
            }
            for selectedElement in selected {
                let nodes = [selectedElement]
                    + AXAccess.descendants(of: selectedElement, maxNodes: 40)
                for node in nodes {
                    guard let selectedURL = AXAccess.url(node, kAXURLAttribute)
                            ?? AXAccess.url(node, kAXDocumentAttribute),
                          let selectedFile = try? DialogSelectionPolicy.validateFile(selectedURL) else {
                        continue
                    }
                    if let identity = target.identity {
                        if selectedFile.identity == identity { return true }
                    } else if selectedFile.url == target.url {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func liveInspection(
        for session: FileDialogSession
    ) -> AXFileDialogInspection? {
        AXUIElementSetMessagingTimeout(session.originalWindow, 0.25)
        var pid: pid_t = 0
        guard AXUIElementGetPid(session.originalWindow, &pid) == .success,
              pid == session.dialogOwnerPID,
              "\(pid):\(CFHash(session.originalWindow))" == session.id,
              AXAccess.rawFrame(session.originalWindow) != nil,
              let inspection = inspector.inspect(
                session.originalWindow,
                maxNodes: 700
              ),
              DialogClassifier.isSupportedFileDialog(inspection.snapshot) else {
            return nil
        }
        return inspection
    }

    private func canContinue(
        _ operation: FileDialogSelectionOperation,
        session: FileDialogSession,
        goToContext: GoToFolderContext
    ) -> Bool {
        guard !operation.isCancelled,
              liveInspection(for: session) != nil,
              isGoToFolderContextLive(goToContext, in: session),
              isFocused(in: goToContext.sheet, session: session) else {
            return false
        }
        return !operation.isCancelled
    }

    private func isGoToFolderContextLive(
        _ context: GoToFolderContext,
        in session: FileDialogSession
    ) -> Bool {
        CFHash(context.sheet) == context.id
            && AXAccess.string(context.sheet, kAXRoleAttribute) == kAXSheetRole as String
            && AXAccess.isAncestor(session.originalWindow, of: context.sheet)
            && AXAccess.isAncestor(context.sheet, of: context.pathField)
            && AXAccess.isAncestor(context.sheet, of: context.defaultButton)
            && isWritablePathField(context.pathField)
            && isGoButton(context.defaultButton)
    }

    private func isFocused(
        in root: AXUIElement,
        session: FileDialogSession
    ) -> Bool {
        guard let focused = focusedElement(for: session) else { return false }
        return AXAccess.isAncestor(root, of: focused.element)
    }

    private func focusedElement(
        for session: FileDialogSession
    ) -> (element: AXUIElement, pid: pid_t)? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApplication = AXAccess.element(
            systemWide,
            kAXFocusedApplicationAttribute
        ),
        let focused = AXAccess.element(
            focusedApplication,
            kAXFocusedUIElementAttribute
        ) else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success,
              pid == session.dialogOwnerPID || pid == session.hostPID,
              AXAccess.isAncestor(session.originalWindow, of: focused) else {
            return nil
        }
        return (focused, pid)
    }

    private func focusedEventTargetPID(for session: FileDialogSession) -> pid_t? {
        focusedElement(for: session)?.pid
    }

    private func postGoToFolderShortcut(
        to pid: pid_t,
        session: FileDialogSession,
        operation: FileDialogSelectionOperation
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_G),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_G),
                keyDown: false
              ) else {
            return false
        }
        keyDown.flags = [.maskCommand, .maskShift]
        keyUp.flags = [.maskCommand, .maskShift]
        guard !operation.isCancelled,
              liveInspection(for: session) != nil,
              focusedEventTargetPID(for: session) == pid,
              !operation.isCancelled else {
            return false
        }
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    private func sheetIDs(in root: AXUIElement) -> Set<CFHashCode> {
        Set(([root] + AXAccess.descendants(of: root, maxNodes: 220)).compactMap { element in
            AXAccess.string(element, kAXRoleAttribute) == kAXSheetRole as String
                ? CFHash(element)
                : nil
        })
    }

    private func poll(
        timeout: TimeInterval,
        interval: TimeInterval,
        step: DialogBridgeStep,
        operation: FileDialogSelectionOperation,
        condition: @escaping () -> Bool,
        completion: @escaping Completion
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        func attempt() {
            guard !operation.isCancelled else { return }
            if condition() {
                completion(.success(()))
                return
            }
            guard Date() < deadline else {
                completion(.failure(.bridgeTimedOut(step)))
                return
            }
            queue.asyncAfter(deadline: .now() + interval, execute: attempt)
        }
        attempt()
    }
}
