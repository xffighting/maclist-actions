import Foundation
@testable import MacListCore
import XCTest

final class SearchEngineTests: XCTestCase {
    func testChineseFilenameMatchRanksBeforePathMatch() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let records = [
            FileRecord(
                path: "/Volumes/TestData/报价项目/普通文件.pdf",
                lastUsedAt: now,
                source: .spotlight
            ),
            FileRecord(
                path: "/Volumes/TestData/Documents/报价清单.xlsx",
                lastUsedAt: now.addingTimeInterval(-3_600),
                source: .spotlight
            )
        ]

        XCTAssertEqual(
            SearchEngine.search("报价", in: records, now: now).map(\.displayName),
            ["报价清单.xlsx", "普通文件.pdf"]
        )
    }

    func testSubsequenceSearchSupportsMultipleTokens() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let record = FileRecord(
            path: "/Volumes/TestData/Documents/Customer-Quotation-2026.xlsx",
            lastUsedAt: now,
            source: .spotlight
        )

        XCTAssertEqual(
            SearchEngine.search("ctmr qttn", in: [record], now: now).count,
            1
        )
    }
}
