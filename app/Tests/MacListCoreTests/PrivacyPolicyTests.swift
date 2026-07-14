import Foundation
@testable import MacListCore
import XCTest

final class PrivacyPolicyTests: XCTestCase {
    private let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testSpotlightPathDoesNotRequireDirectFileAccess() {
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/tester/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
    }

    func testSpotlightPathAllowsCloudDocumentContainers() {
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/资料/云端报价.pdf",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/tester/Library/CloudStorage/OneDrive/Documents/年度报价.xlsx",
                homeDirectory: homeDirectory
            )
        )
    }

    func testSpotlightPathStillAppliesPrivacyBoundaries() {
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/tester/.Trash/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/another/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/Users/tester/Library/Application Support/secret.txt",
                homeDirectory: homeDirectory
            )
        )
    }
}
