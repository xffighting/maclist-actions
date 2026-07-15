import AppKit
import ApplicationServices
import Carbon
import Darwin
import MacListCore

final class FileDialogSession {
    let id: String
    let hostPID: pid_t
    let dialogOwnerPID: pid_t
    let originalWindow: AXUIElement
    let originalFocusedElement: AXUIElement
    let hostApplicationName: String
    let dialogKind: DialogKind
    let originalWindowRole: String
    let originalAuthoritativeDefaultButton: AXUIElement?

    init(
        id: String,
        hostPID: pid_t,
        dialogOwnerPID: pid_t,
        originalWindow: AXUIElement,
        originalFocusedElement: AXUIElement,
        hostApplicationName: String,
        dialogKind: DialogKind,
        originalWindowRole: String,
        originalAuthoritativeDefaultButton: AXUIElement?
    ) {
        self.id = id
        self.hostPID = hostPID
        self.dialogOwnerPID = dialogOwnerPID
        self.originalWindow = originalWindow
        self.originalFocusedElement = originalFocusedElement
        self.hostApplicationName = hostApplicationName
        self.dialogKind = dialogKind
        self.originalWindowRole = originalWindowRole
        self.originalAuthoritativeDefaultButton = originalAuthoritativeDefaultButton
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

    fileprivate func performIfActive(_ action: () -> AXError?) -> AXError? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, !cancelled else { return nil }
        return action()
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
        interactionLease: FileDialogInteractionLease? = nil,
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
            target = try DialogSelectionPolicy.validateCandidate(url)
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
        guard mode == .selectOnly
                || (mode == .selectAndConfirm
                    && session.dialogKind == .openFile
                    && interactionLease?.isValid(for: session.id) == true) else {
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
                        interactionLease: interactionLease,
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
        interactionLease: FileDialogInteractionLease?,
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
                    interactionLease: interactionLease,
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
        interactionLease: FileDialogInteractionLease?,
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
                    interactionLease: interactionLease,
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
        interactionLease: FileDialogInteractionLease?,
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
                if self.isSelectionVerified(
                    target,
                    in: currentContainers,
                    requireExactSelection: mode == .selectAndConfirm,
                    session: session
                ) {
                    return true
                }
                if Date().timeIntervalSince(lastContainerRefresh) >= 0.35,
                   let inspection = self.liveInspection(for: session) {
                    currentContainers = inspection.fileContainers
                    lastContainerRefresh = Date()
                    return self.isSelectionVerified(
                        target,
                        in: currentContainers,
                        requireExactSelection: mode == .selectAndConfirm,
                        session: session
                    )
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
                      self.isSelectionVerified(
                        target,
                        in: finalInspection.fileContainers,
                        requireExactSelection: mode == .selectAndConfirm,
                        session: session
                      ) else {
                    completion(.failure(.selectionCouldNotBeVerified(target.url.path)))
                    return
                }
                switch mode {
                case .selectOnly:
                    completion(.success(()))
                case .selectAndConfirm:
                    self.confirmExactSelection(
                        target,
                        session: session,
                        operation: operation,
                        interactionLease: interactionLease,
                        completion: completion
                    )
                }
            }
        }
    }

    private struct AXSelectionSnapshot {
        let selectedPaths: [String]
        let hasUnresolvedSelection: Bool
    }

    private struct AXExactSelectionProof {
        let snapshot: AXSelectionSnapshot
        let authoritativeContainer: AXUIElement
    }

    private func isSelectionVerified(
        _ target: ValidatedFile,
        in fileContainers: [AXUIElement],
        requireExactSelection: Bool,
        session: FileDialogSession
    ) -> Bool {
        if requireExactSelection {
            return exactSelectionSnapshot(
                for: target,
                in: fileContainers,
                session: session
            ) != nil
        }
        let snapshot = selectionSnapshot(in: fileContainers)
        guard let normalizedTarget = DialogConfirmationSafetyPolicy
            .normalizedFilePath(target.url) else {
            return false
        }
        return snapshot.selectedPaths.contains(normalizedTarget)
    }

    private func selectionSnapshot(
        in fileContainers: [AXUIElement]
    ) -> AXSelectionSnapshot {
        var selectedElements: [AXUIElement] = []
        for container in fileContainers {
            AXUIElementSetMessagingTimeout(container, 0.15)
            let selectionRoots = [container]
                + AXAccess.descendants(of: container, maxNodes: 80)
            for selectionRoot in selectionRoots {
                AXUIElementSetMessagingTimeout(selectionRoot, 0.12)
                let selected = AXAccess.elements(
                    selectionRoot,
                    kAXSelectedChildrenAttribute
                )
                    + AXAccess.elements(selectionRoot, kAXSelectedRowsAttribute)
                for element in selected where !selectedElements.contains(
                    where: { AXAccess.isSame($0, element) }
                ) {
                    selectedElements.append(element)
                }
            }
        }

        return resolvedSelectionSnapshot(
            selectedElements,
            hasUnresolvedSelection: false
        )
    }

    private func resolvedSelectionSnapshot(
        _ selectedElements: [AXUIElement],
        hasUnresolvedSelection initialUnresolvedSelection: Bool
    ) -> AXSelectionSnapshot {
        var selectedPaths: [String] = []
        var hasUnresolvedSelection = initialUnresolvedSelection
        for selectedElement in selectedElements {
            AXUIElementSetMessagingTimeout(selectedElement, 0.08)
            let nodes = [selectedElement]
                + AXAccess.descendants(of: selectedElement, maxNodes: 40)
            var pathsForElement: [String] = []
            var sawInvalidURL = false
            for node in nodes {
                for attribute in [kAXURLAttribute, kAXDocumentAttribute] {
                    guard AXAccess.value(node, attribute) != nil else { continue }
                    guard let selectedURL = AXAccess.url(node, attribute),
                          let path = DialogConfirmationSafetyPolicy
                            .normalizedFilePath(selectedURL) else {
                        sawInvalidURL = true
                        continue
                    }
                    if !pathsForElement.contains(path) {
                        pathsForElement.append(path)
                    }
                }
            }
            if pathsForElement.isEmpty || sawInvalidURL {
                hasUnresolvedSelection = true
            }
            for path in pathsForElement where !selectedPaths.contains(path) {
                selectedPaths.append(path)
            }
        }

        return AXSelectionSnapshot(
            selectedPaths: selectedPaths,
            hasUnresolvedSelection: hasUnresolvedSelection
        )
    }

    /// The file browser that currently owns keyboard focus is the only
    /// authoritative selection source. Sidebars and inactive column browsers
    /// expose unrelated selected folders and are deliberately ignored.
    private func exactSelectionSnapshot(
        for target: ValidatedFile,
        in fileContainers: [AXUIElement],
        session: FileDialogSession
    ) -> AXExactSelectionProof? {
        guard let focused = focusedElement(for: session)?.element,
              let authoritativeContainer = nearestInspectedFileContainer(
                from: focused,
                candidates: fileContainers
              ),
              let normalizedTarget = DialogConfirmationSafetyPolicy
                .normalizedFilePath(target.url) else {
            return nil
        }

        var focusedProof: AXExactSelectionProof?
        for container in fileContainers {
            let selectedElements: [AXUIElement]
            switch directlySelectedElements(in: container) {
            case .unsupported:
                continue
            case .failed:
                // A transient/partial AX read could hide another selected row.
                return nil
            case let .reliable(elements):
                selectedElements = elements
            }

            let snapshot = resolvedSelectionSnapshot(
                selectedElements,
                hasUnresolvedSelection: false
            )
            guard snapshot.selectedPaths.contains(normalizedTarget) else {
                continue
            }
            guard DialogConfirmationSafetyPolicy.isExactSelection(
                targetPath: target.url.path,
                selectedPaths: snapshot.selectedPaths,
                hasUnresolvedSelection: snapshot.hasUnresolvedSelection
            ) else {
                // Every AX container that exposes the target must agree that
                // the target is the sole resolved selection. This rejects a
                // nested child that hides a second row exposed by its parent.
                return nil
            }
            if AXAccess.isSame(container, authoritativeContainer) {
                focusedProof = AXExactSelectionProof(
                    snapshot: snapshot,
                    authoritativeContainer: container
                )
            }
        }
        return focusedProof
    }

    private func directExactSelectionSnapshot(
        for target: ValidatedFile,
        in container: AXUIElement
    ) -> AXSelectionSnapshot? {
        guard case let .reliable(selectedElements) = directlySelectedElements(
            in: container
        ) else {
            return nil
        }
        let snapshot = resolvedSelectionSnapshot(
            selectedElements,
            hasUnresolvedSelection: false
        )
        guard DialogConfirmationSafetyPolicy.isExactSelection(
            targetPath: target.url.path,
            selectedPaths: snapshot.selectedPaths,
            hasUnresolvedSelection: snapshot.hasUnresolvedSelection
        ) else {
            return nil
        }
        return snapshot
    }

    private func nearestInspectedFileContainer(
        from element: AXUIElement,
        candidates: [AXUIElement]
    ) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<24 {
            guard let candidate = current else { return nil }
            if candidates.contains(where: { AXAccess.isSame($0, candidate) }) {
                return candidate
            }
            current = AXAccess.element(candidate, kAXParentAttribute)
        }
        return nil
    }

    private enum DirectSelectionRead {
        case unsupported
        case reliable([AXUIElement])
        case failed
    }

    private func directlySelectedElements(
        in container: AXUIElement
    ) -> DirectSelectionRead {
        AXUIElementSetMessagingTimeout(container, 0.08)
        var selectedElements: [AXUIElement] = []
        var successfulReadCount = 0
        var sawReadFailure = false

        for attribute in [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute] {
            var rawValue: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                container,
                attribute as CFString,
                &rawValue
            )
            switch status {
            case .success:
                successfulReadCount += 1
                guard let rawValue,
                      CFGetTypeID(rawValue) == CFArrayGetTypeID(),
                      let elements = rawValue as? [AXUIElement] else {
                    sawReadFailure = true
                    continue
                }
                guard elements.count <= 32 else { return .failed }
                for element in elements where !selectedElements.contains(
                    where: { AXAccess.isSame($0, element) }
                ) {
                    selectedElements.append(element)
                    if selectedElements.count > 32 { return .failed }
                }
            case .attributeUnsupported, .noValue:
                continue
            default:
                sawReadFailure = true
            }
        }

        if sawReadFailure { return .failed }
        if successfulReadCount == 0 { return .unsupported }
        return .reliable(selectedElements)
    }

    private func confirmExactSelection(
        _ target: ValidatedFile,
        session: FileDialogSession,
        operation: FileDialogSelectionOperation,
        interactionLease: FileDialogInteractionLease?,
        completion: @escaping Completion
    ) {
        guard let interactionLease,
              let capturedDefaultButton = session.originalAuthoritativeDefaultButton,
              let inspection = liveInspection(for: session),
              let authoritativeDefaultButton = inspection.authoritativeDefaultButton else {
            completion(.failure(.automaticConfirmationRefused))
            return
        }

        guard let selectionProof = exactSelectionSnapshot(
            for: target,
            in: inspection.fileContainers,
            session: session
        ) else {
            completion(.failure(.automaticConfirmationRefused))
            return
        }
        var windowPID: pid_t = 0
        var buttonPID: pid_t = 0
        let windowPIDMatchesOwner = AXUIElementGetPid(
            session.originalWindow,
            &windowPID
        ) == .success && windowPID == session.dialogOwnerPID
        let buttonPIDMatchesOwner = AXUIElementGetPid(
            authoritativeDefaultButton,
            &buttonPID
        ) == .success && buttonPID == session.dialogOwnerPID
        let windowRole = AXAccess.string(
            session.originalWindow,
            kAXRoleAttribute
        )
        let focused = focusedElement(for: session)?.element
        let buttonDialogRoot = capturedDialogRoot(for: authoritativeDefaultButton)
        let focusedDialogRoot = focused.flatMap(capturedDialogRoot)
        let buttonIsAuthoritativeDefault = AXAccess.isSame(
            authoritativeDefaultButton,
            capturedDefaultButton
        ) && AXAccess.element(
            session.originalWindow,
            kAXDefaultButtonAttribute
        ).map { AXAccess.isSame($0, authoritativeDefaultButton) } == true

        let context = DialogConfirmationSafetyContext(
            mode: .selectAndConfirm,
            sessionKind: session.dialogKind,
            freshKind: inspection.kind,
            hasSaveFilenameField: inspection.hasSaveFilenameField,
            defaultButtonTitle: AXAccess.string(
                authoritativeDefaultButton,
                kAXTitleAttribute
            ),
            targetPath: target.url.path,
            selectedPaths: selectionProof.snapshot.selectedPaths,
            hasUnresolvedSelection: selectionProof.snapshot.hasUnresolvedSelection,
            isCurrentSession: interactionLease.isValid(for: session.id),
            isOperationActive: !operation.isCancelled,
            ownerIsRunning: processIsRunning(session.dialogOwnerPID),
            originalWindowIsVisible: AXAccess.rawFrame(session.originalWindow) != nil
                && !inspection.snapshot.isMinimized
                && !inspection.snapshot.isHidden,
            hasCancelButton: inspection.snapshot.hasCancelButton,
            windowPIDMatchesOwner: windowPIDMatchesOwner,
            buttonPIDMatchesOwner: buttonPIDMatchesOwner,
            windowRoleIsSupported: windowRole == session.originalWindowRole
                && [kAXWindowRole as String, kAXSheetRole as String].contains(
                    windowRole ?? ""
                ),
            buttonRoleIsButton: AXAccess.string(
                authoritativeDefaultButton,
                kAXRoleAttribute
            ) == kAXButtonRole as String,
            buttonIsAuthoritativeDefault: buttonIsAuthoritativeDefault,
            buttonIsDescendantOfOriginalWindow: AXAccess.isAncestor(
                session.originalWindow,
                of: authoritativeDefaultButton
            ),
            topLevelMatchesOriginalWindow: buttonDialogRoot.map {
                AXAccess.isSame($0, session.originalWindow)
            } == true,
            originalWindowIsFocused: focused.map {
                AXAccess.isAncestor(session.originalWindow, of: $0)
            } == true && focusedDialogRoot.map {
                AXAccess.isSame($0, session.originalWindow)
            } == true,
            buttonIsEnabled: AXAccess.bool(
                authoritativeDefaultButton,
                kAXEnabledAttribute
            ) == true,
            buttonSupportsPress: AXAccess.supportsPress(
                authoritativeDefaultButton
            )
        )

        guard case .allow = DialogConfirmationSafetyPolicy.decision(for: context) else {
            Diagnostics.log("auto_confirm_refused")
            completion(.failure(.automaticConfirmationRefused))
            return
        }

        // Perform the expensive 700-node inspection and exact-selection proof
        // before taking either state lock. This keeps detach/invalidate
        // responsive even when the target process has a slow AX tree.
        guard let currentInspection = liveInspection(for: session),
              currentInspection.kind == .openFile,
              !currentInspection.hasSaveFilenameField,
              currentInspection.snapshot.hasCancelButton,
              let currentButton = currentInspection.authoritativeDefaultButton,
              AXAccess.isSame(currentButton, authoritativeDefaultButton),
              AXAccess.isSame(currentButton, capturedDefaultButton),
              let currentSelectionProof = exactSelectionSnapshot(
                for: target,
                in: currentInspection.fileContainers,
                session: session
              ),
              interactionLease.consumeIfValid(for: session.id) else {
            completion(.failure(.automaticConfirmationRefused))
            return
        }

        // The lease has now been consumed forever. The operation lock covers
        // only the final narrow identity/focus checks and the single AXPress;
        // cancellation can prevent entry, and no path can retry afterward.
        let pressStatus = operation.performIfActive {
            guard let finalButton = AXAccess.element(
                    session.originalWindow,
                    kAXDefaultButtonAttribute
                  ),
                  AXAccess.isSame(finalButton, currentButton),
                  AXAccess.isSame(finalButton, capturedDefaultButton),
                  AXAccess.string(finalButton, kAXRoleAttribute)
                    == kAXButtonRole as String,
                  AXAccess.bool(finalButton, kAXEnabledAttribute) == true,
                  AXAccess.supportsPress(finalButton),
                  AXAccess.isAncestor(session.originalWindow, of: finalButton),
                  self.capturedDialogRoot(for: finalButton).map({
                    AXAccess.isSame($0, session.originalWindow)
                  }) == true,
                  self.focusedElement(for: session).map({ focused in
                    self.nearestInspectedFileContainer(
                        from: focused.element,
                        candidates: currentInspection.fileContainers
                    ).map {
                        AXAccess.isSame(
                            $0,
                            currentSelectionProof.authoritativeContainer
                        )
                    } == true
                  }) == true,
                  self.directExactSelectionSnapshot(
                    for: target,
                    in: currentSelectionProof.authoritativeContainer
                  ) != nil,
                  DialogSelectionPolicy.confirmationDecision(
                    for: DialogConfirmationContext(
                        kind: currentInspection.kind,
                        defaultButtonTitle: AXAccess.string(
                            finalButton,
                            kAXTitleAttribute
                        ),
                        exactSelectionVerified: true,
                        isCurrentSession: true
                    )
                  ) == .allow else {
                return nil
            }
            return AXAccess.press(finalButton)
        }

        guard let pressStatus else {
            completion(.failure(.automaticConfirmationRefused))
            return
        }
        Diagnostics.log("auto_confirm_press_\(pressStatus.rawValue)")
        observeOriginalDialogClosure(
            session,
            completion: completion
        )
    }

    private func capturedDialogRoot(for element: AXUIElement) -> AXUIElement? {
        AXAccess.nearestAncestor(
            from: element,
            matching: [kAXSheetRole as String, kAXWindowRole as String]
        )
    }

    private func processIsRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func observeOriginalDialogClosure(
        _ session: FileDialogSession,
        completion: @escaping Completion
    ) {
        let deadline = Date().addingTimeInterval(1.5)
        var consecutiveClosedChecks = 0

        func attempt() {
            if self.originalDialogIsPresent(session) {
                consecutiveClosedChecks = 0
            } else {
                consecutiveClosedChecks += 1
                if consecutiveClosedChecks >= 2 {
                    completion(.success(()))
                    return
                }
            }
            guard Date() < deadline else {
                completion(.failure(.confirmationResultUncertain))
                return
            }
            self.queue.asyncAfter(deadline: .now() + 0.06, execute: attempt)
        }
        attempt()
    }

    private func originalDialogIsPresent(_ session: FileDialogSession) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(session.originalWindow, &pid) == .success,
              pid == session.dialogOwnerPID,
              "\(pid):\(CFHash(session.originalWindow))" == session.id,
              AXAccess.string(session.originalWindow, kAXRoleAttribute)
                == session.originalWindowRole,
              AXAccess.rawFrame(session.originalWindow) != nil else {
            return false
        }
        return true
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
              inspection.snapshot.role == session.originalWindowRole,
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
