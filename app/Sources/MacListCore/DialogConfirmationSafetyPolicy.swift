import Foundation

/// A side-effect-free snapshot of every fact that must still be true
/// immediately before MacList presses the original Open Panel default button.
public struct DialogConfirmationSafetyContext: Equatable, Sendable {
    public let mode: DialogSelectionMode
    public let sessionKind: DialogKind
    public let freshKind: DialogKind
    public let hasSaveFilenameField: Bool
    public let defaultButtonTitle: String?
    public let targetPath: String
    public let selectedPaths: [String]
    public let hasUnresolvedSelection: Bool
    public let isCurrentSession: Bool
    public let isOperationActive: Bool
    public let ownerIsRunning: Bool
    public let originalWindowIsVisible: Bool
    public let hasCancelButton: Bool
    public let windowPIDMatchesOwner: Bool
    public let buttonPIDMatchesOwner: Bool
    public let windowRoleIsSupported: Bool
    public let buttonRoleIsButton: Bool
    public let buttonIsAuthoritativeDefault: Bool
    public let buttonIsDescendantOfOriginalWindow: Bool
    public let topLevelMatchesOriginalWindow: Bool
    public let originalWindowIsFocused: Bool
    public let buttonIsEnabled: Bool
    public let buttonSupportsPress: Bool

    public init(
        mode: DialogSelectionMode,
        sessionKind: DialogKind,
        freshKind: DialogKind,
        hasSaveFilenameField: Bool,
        defaultButtonTitle: String?,
        targetPath: String,
        selectedPaths: [String],
        hasUnresolvedSelection: Bool,
        isCurrentSession: Bool,
        isOperationActive: Bool,
        ownerIsRunning: Bool,
        originalWindowIsVisible: Bool,
        hasCancelButton: Bool,
        windowPIDMatchesOwner: Bool,
        buttonPIDMatchesOwner: Bool,
        windowRoleIsSupported: Bool,
        buttonRoleIsButton: Bool,
        buttonIsAuthoritativeDefault: Bool,
        buttonIsDescendantOfOriginalWindow: Bool,
        topLevelMatchesOriginalWindow: Bool,
        originalWindowIsFocused: Bool,
        buttonIsEnabled: Bool,
        buttonSupportsPress: Bool
    ) {
        self.mode = mode
        self.sessionKind = sessionKind
        self.freshKind = freshKind
        self.hasSaveFilenameField = hasSaveFilenameField
        self.defaultButtonTitle = defaultButtonTitle
        self.targetPath = targetPath
        self.selectedPaths = selectedPaths
        self.hasUnresolvedSelection = hasUnresolvedSelection
        self.isCurrentSession = isCurrentSession
        self.isOperationActive = isOperationActive
        self.ownerIsRunning = ownerIsRunning
        self.originalWindowIsVisible = originalWindowIsVisible
        self.hasCancelButton = hasCancelButton
        self.windowPIDMatchesOwner = windowPIDMatchesOwner
        self.buttonPIDMatchesOwner = buttonPIDMatchesOwner
        self.windowRoleIsSupported = windowRoleIsSupported
        self.buttonRoleIsButton = buttonRoleIsButton
        self.buttonIsAuthoritativeDefault = buttonIsAuthoritativeDefault
        self.buttonIsDescendantOfOriginalWindow = buttonIsDescendantOfOriginalWindow
        self.topLevelMatchesOriginalWindow = topLevelMatchesOriginalWindow
        self.originalWindowIsFocused = originalWindowIsFocused
        self.buttonIsEnabled = buttonIsEnabled
        self.buttonSupportsPress = buttonSupportsPress
    }
}

public enum DialogConfirmationSafetyDenialReason: Equatable, Sendable {
    case wrongMode
    case unsupportedSessionKind(DialogKind)
    case unsupportedFreshKind(DialogKind)
    case saveFilenameFieldPresent
    case unsafeDefaultAction
    case exactSelectionNotVerified
    case staleDialogSession
    case inactiveOperation
    case ownerUnavailable
    case originalWindowNotVisible
    case cancelActionUnavailable
    case windowPIDMismatch
    case buttonPIDMismatch
    case unsupportedWindowRole
    case unsupportedButtonRole
    case buttonIsNotAuthoritativeDefault
    case buttonOutsideOriginalWindow
    case topLevelMismatch
    case originalWindowNotFocused
    case buttonDisabled
    case pressActionUnavailable
}

public enum DialogConfirmationSafetyDecision: Equatable, Sendable {
    case allow
    case deny(DialogConfirmationSafetyDenialReason)
}

public enum DialogConfirmationSafetyPolicy {
    public static func decision(
        for context: DialogConfirmationSafetyContext
    ) -> DialogConfirmationSafetyDecision {
        guard context.mode == .selectAndConfirm else {
            return .deny(.wrongMode)
        }
        guard context.sessionKind == .openFile else {
            return .deny(.unsupportedSessionKind(context.sessionKind))
        }
        guard context.freshKind == .openFile else {
            return .deny(.unsupportedFreshKind(context.freshKind))
        }
        guard !context.hasSaveFilenameField else {
            return .deny(.saveFilenameFieldPresent)
        }
        guard context.isCurrentSession else {
            return .deny(.staleDialogSession)
        }
        guard context.isOperationActive else {
            return .deny(.inactiveOperation)
        }

        // Reuse the single explicit-title allowlist. The structural gate below
        // deliberately does not maintain a second copy of those strings.
        let titleDecision = DialogSelectionPolicy.confirmationDecision(
            for: DialogConfirmationContext(
                kind: context.freshKind,
                defaultButtonTitle: context.defaultButtonTitle,
                exactSelectionVerified: isExactSelection(
                    targetPath: context.targetPath,
                    selectedPaths: context.selectedPaths,
                    hasUnresolvedSelection: context.hasUnresolvedSelection
                ),
                isCurrentSession: context.isCurrentSession
            )
        )
        switch titleDecision {
        case .allow:
            break
        case .deny(.exactSelectionNotVerified):
            return .deny(.exactSelectionNotVerified)
        case .deny(.unsafeDefaultAction):
            return .deny(.unsafeDefaultAction)
        case .deny(.staleDialogSession):
            return .deny(.staleDialogSession)
        case .deny(.unsupportedDialogKind):
            return .deny(.unsupportedFreshKind(context.freshKind))
        }

        guard context.ownerIsRunning else { return .deny(.ownerUnavailable) }
        guard context.originalWindowIsVisible else {
            return .deny(.originalWindowNotVisible)
        }
        guard context.hasCancelButton else {
            return .deny(.cancelActionUnavailable)
        }
        guard context.windowPIDMatchesOwner else { return .deny(.windowPIDMismatch) }
        guard context.buttonPIDMatchesOwner else { return .deny(.buttonPIDMismatch) }
        guard context.windowRoleIsSupported else { return .deny(.unsupportedWindowRole) }
        guard context.buttonRoleIsButton else { return .deny(.unsupportedButtonRole) }
        guard context.buttonIsAuthoritativeDefault else {
            return .deny(.buttonIsNotAuthoritativeDefault)
        }
        guard context.buttonIsDescendantOfOriginalWindow else {
            return .deny(.buttonOutsideOriginalWindow)
        }
        guard context.topLevelMatchesOriginalWindow else {
            return .deny(.topLevelMismatch)
        }
        guard context.originalWindowIsFocused else {
            return .deny(.originalWindowNotFocused)
        }
        guard context.buttonIsEnabled else { return .deny(.buttonDisabled) }
        guard context.buttonSupportsPress else { return .deny(.pressActionUnavailable) }
        return .allow
    }

    public static func normalizedFilePath(_ url: URL) -> String? {
        guard url.isFileURL, !url.path.isEmpty else { return nil }
        return url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    public static func isExactSelection(
        targetPath: String,
        selectedPaths: [String],
        hasUnresolvedSelection: Bool
    ) -> Bool {
        guard !hasUnresolvedSelection else { return false }
        let target = URL(fileURLWithPath: targetPath)
        guard let normalizedTarget = normalizedFilePath(target) else { return false }
        let normalizedSelections = Set(selectedPaths.compactMap { path in
            normalizedFilePath(URL(fileURLWithPath: path))
        })
        return normalizedSelections == Set([normalizedTarget])
    }
}
