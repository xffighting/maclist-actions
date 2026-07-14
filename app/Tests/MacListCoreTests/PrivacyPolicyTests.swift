import Foundation
@testable import MacListCore
import XCTest

final class PrivacyPolicyTests: XCTestCase {
    private let homeDirectory = URL(fileURLWithPath: "/tmp/maclist-test-home", isDirectory: true)

    func testSpotlightPathDoesNotRequireDirectFileAccess() {
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-test-home/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
    }

    func testSpotlightPathAllowsCloudDocumentContainers() {
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-test-home/Library/Mobile Documents/com~apple~CloudDocs/资料/云端报价.pdf",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertTrue(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-test-home/Library/CloudStorage/OneDrive/Documents/年度报价.xlsx",
                homeDirectory: homeDirectory
            )
        )
    }

    func testSpotlightPathStillAppliesPrivacyBoundaries() {
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-test-home/.Trash/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-other-home/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        XCTAssertFalse(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-test-home/Library/Application Support/secret.txt",
                homeDirectory: homeDirectory
            )
        )
    }
}
