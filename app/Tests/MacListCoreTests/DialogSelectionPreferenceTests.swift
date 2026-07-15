import Foundation
@testable import MacListCore
import XCTest

final class DialogSelectionPreferenceTests: XCTestCase {
    func testFreshPreferenceDefaultsToSelectingAndConfirming() {
        withIsolatedDefaults { defaults in
            let preference = DialogSelectionPreference(userDefaults: defaults)

            XCTAssertEqual(preference.mode, .selectAndConfirm)
        }
    }

    func testSelectedModePersistsAcrossPreferenceInstances() {
        withIsolatedDefaults { defaults in
            DialogSelectionPreference(userDefaults: defaults).mode = .selectOnly

            let restored = DialogSelectionPreference(userDefaults: defaults)
            XCTAssertEqual(restored.mode, .selectOnly)
        }
    }

    func testToggleMovesBetweenAutomaticConfirmationAndSelectOnly() {
        withIsolatedDefaults { defaults in
            let preference = DialogSelectionPreference(userDefaults: defaults)

            XCTAssertEqual(preference.toggle(), .selectOnly)
            XCTAssertEqual(preference.mode, .selectOnly)
            XCTAssertEqual(preference.toggle(), .selectAndConfirm)
            XCTAssertEqual(preference.mode, .selectAndConfirm)
        }
    }

    func testUnknownStoredValueFallsBackToDefaultMode() {
        withIsolatedDefaults { defaults in
            defaults.set("future-mode", forKey: DialogSelectionPreference.defaultKey)

            let preference = DialogSelectionPreference(userDefaults: defaults)
            XCTAssertEqual(preference.mode, .selectAndConfirm)
        }
    }

    private func withIsolatedDefaults(
        _ body: (UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "DialogSelectionPreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
