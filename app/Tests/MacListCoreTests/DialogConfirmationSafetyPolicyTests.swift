import Foundation
@testable import MacListCore
import XCTest

final class DialogConfirmationSafetyPolicyTests: XCTestCase {
    private let targetPath = "/tmp/客户/报价单.pdf"

    func testAllowsOnlyACompleteCurrentOpenFileConfirmationSnapshot() {
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.decision(for: safeContext()),
            .allow
        )
    }

    func testRejectsEveryMissingStructuralPrecondition() {
        let denied: [(DialogConfirmationSafetyContext, DialogConfirmationSafetyDenialReason)] = [
            (safeContext(mode: .selectOnly), .wrongMode),
            (safeContext(sessionKind: .save), .unsupportedSessionKind(.save)),
            (safeContext(freshKind: .unknown), .unsupportedFreshKind(.unknown)),
            (safeContext(hasSaveFilenameField: true), .saveFilenameFieldPresent),
            (safeContext(isCurrentSession: false), .staleDialogSession),
            (safeContext(isOperationActive: false), .inactiveOperation),
            (safeContext(ownerIsRunning: false), .ownerUnavailable),
            (safeContext(originalWindowIsVisible: false), .originalWindowNotVisible),
            (safeContext(hasCancelButton: false), .cancelActionUnavailable),
            (safeContext(windowPIDMatchesOwner: false), .windowPIDMismatch),
            (safeContext(buttonPIDMatchesOwner: false), .buttonPIDMismatch),
            (safeContext(windowRoleIsSupported: false), .unsupportedWindowRole),
            (safeContext(buttonRoleIsButton: false), .unsupportedButtonRole),
            (safeContext(buttonIsAuthoritativeDefault: false), .buttonIsNotAuthoritativeDefault),
            (safeContext(buttonIsDescendantOfOriginalWindow: false), .buttonOutsideOriginalWindow),
            (safeContext(topLevelMatchesOriginalWindow: false), .topLevelMismatch),
            (safeContext(originalWindowIsFocused: false), .originalWindowNotFocused),
            (safeContext(buttonIsEnabled: false), .buttonDisabled),
            (safeContext(buttonSupportsPress: false), .pressActionUnavailable)
        ]

        for (context, reason) in denied {
            XCTAssertEqual(
                DialogConfirmationSafetyPolicy.decision(for: context),
                .deny(reason),
                "Expected denial for \(reason)"
            )
        }
    }

    func testRejectsUnsafeDefaultButtonTitles() {
        for title in [nil, "", "OK", "Save", "Send", "Open and Send"] as [String?] {
            XCTAssertEqual(
                DialogConfirmationSafetyPolicy.decision(
                    for: safeContext(defaultButtonTitle: title)
                ),
                .deny(.unsafeDefaultAction)
            )
        }
    }

    func testRejectsMultipleOrUnresolvedSelections() {
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.decision(
                for: safeContext(selectedPaths: [targetPath, "/tmp/客户/其他.pdf"])
            ),
            .deny(.exactSelectionNotVerified)
        )
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.decision(
                for: safeContext(hasUnresolvedSelection: true)
            ),
            .deny(.exactSelectionNotVerified)
        )
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.decision(
                for: safeContext(selectedPaths: [])
            ),
            .deny(.exactSelectionNotVerified)
        )
    }

    func testDuplicateAXRepresentationsOfTheSameNormalizedURLAreSafe() {
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.decision(
                for: safeContext(selectedPaths: [targetPath, targetPath])
            ),
            .allow
        )
    }

    func testFileURLNormalizationIsLexicalAndRejectsNonFileURLs() {
        XCTAssertEqual(
            DialogConfirmationSafetyPolicy.normalizedFilePath(
                URL(fileURLWithPath: "/tmp/客户/旧目录/../报价单.pdf")
            ),
            targetPath
        )
        XCTAssertNil(
            DialogConfirmationSafetyPolicy.normalizedFilePath(
                URL(string: "https://example.com/报价单.pdf")!
            )
        )
    }

    private func safeContext(
        mode: DialogSelectionMode = .selectAndConfirm,
        sessionKind: DialogKind = .openFile,
        freshKind: DialogKind = .openFile,
        hasSaveFilenameField: Bool = false,
        defaultButtonTitle: String? = "Open",
        selectedPaths: [String]? = nil,
        hasUnresolvedSelection: Bool = false,
        isCurrentSession: Bool = true,
        isOperationActive: Bool = true,
        ownerIsRunning: Bool = true,
        originalWindowIsVisible: Bool = true,
        hasCancelButton: Bool = true,
        windowPIDMatchesOwner: Bool = true,
        buttonPIDMatchesOwner: Bool = true,
        windowRoleIsSupported: Bool = true,
        buttonRoleIsButton: Bool = true,
        buttonIsAuthoritativeDefault: Bool = true,
        buttonIsDescendantOfOriginalWindow: Bool = true,
        topLevelMatchesOriginalWindow: Bool = true,
        originalWindowIsFocused: Bool = true,
        buttonIsEnabled: Bool = true,
        buttonSupportsPress: Bool = true
    ) -> DialogConfirmationSafetyContext {
        DialogConfirmationSafetyContext(
            mode: mode,
            sessionKind: sessionKind,
            freshKind: freshKind,
            hasSaveFilenameField: hasSaveFilenameField,
            defaultButtonTitle: defaultButtonTitle,
            targetPath: targetPath,
            selectedPaths: selectedPaths ?? [targetPath],
            hasUnresolvedSelection: hasUnresolvedSelection,
            isCurrentSession: isCurrentSession,
            isOperationActive: isOperationActive,
            ownerIsRunning: ownerIsRunning,
            originalWindowIsVisible: originalWindowIsVisible,
            hasCancelButton: hasCancelButton,
            windowPIDMatchesOwner: windowPIDMatchesOwner,
            buttonPIDMatchesOwner: buttonPIDMatchesOwner,
            windowRoleIsSupported: windowRoleIsSupported,
            buttonRoleIsButton: buttonRoleIsButton,
            buttonIsAuthoritativeDefault: buttonIsAuthoritativeDefault,
            buttonIsDescendantOfOriginalWindow: buttonIsDescendantOfOriginalWindow,
            topLevelMatchesOriginalWindow: topLevelMatchesOriginalWindow,
            originalWindowIsFocused: originalWindowIsFocused,
            buttonIsEnabled: buttonIsEnabled,
            buttonSupportsPress: buttonSupportsPress
        )
    }
}
