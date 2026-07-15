import Foundation
import XCTest
@testable import MacListCore

final class SearchResultSetTests: XCTestCase {
    func testSpotlightAndLocalIndexCanBeReplacedIndependently() {
        let spotlight = record("/资料/Spotlight-合同.pdf", source: .spotlight, offset: 30)
        let local = record("/资料/客户/本地-清单.xlsx", source: .localIndex, offset: 20)
        var results = SearchResultSet()

        results.replace([spotlight], source: .spotlight)
        results.replace([local], source: .localIndex)

        XCTAssertEqual(Set(results.allRecords.map(\.path)), Set([spotlight.path, local.path]))
    }

    func testReplacingSourceRemovesThatSourcesPreviousQueryResults() {
        let oldSpotlight = record("/资料/旧查询.pdf", source: .spotlight, offset: 30)
        let newSpotlight = record("/资料/新查询.pdf", source: .spotlight, offset: 20)
        let local = record("/资料/客户/本地结果.pdf", source: .localIndex, offset: 10)
        var results = SearchResultSet()
        results.replace([oldSpotlight], source: .spotlight)
        results.replace([local], source: .localIndex)

        results.replace([newSpotlight], source: .spotlight)

        XCTAssertEqual(Set(results.allRecords.map(\.path)), Set([newSpotlight.path, local.path]))
        XCTAssertFalse(results.allRecords.contains { $0.path == oldSpotlight.path })
    }

    func testClearingLocalIndexDoesNotClearSpotlight() {
        let spotlight = record("/资料/Spotlight-合同.pdf", source: .spotlight, offset: 20)
        let local = record("/资料/客户/本地-清单.xlsx", source: .localIndex, offset: 10)
        var results = SearchResultSet()
        results.replace([spotlight], source: .spotlight)
        results.replace([local], source: .localIndex)

        results.clear(source: .localIndex)

        XCTAssertEqual(results.allRecords, [spotlight])
    }

    func testLocalIndexWinsWhenSourcesContainTheSamePath() {
        let sharedPath = "/资料/远航工业/阿曼项目/最终清单.xlsx"
        let spotlight = FileRecord(
            path: sharedPath,
            displayName: "Spotlight 最终清单.xlsx",
            lastUsedAt: Date(timeIntervalSince1970: 2_000_000_000),
            source: .spotlight
        )
        let local = FileRecord(
            path: sharedPath,
            displayName: "本地索引 最终清单.xlsx",
            lastUsedAt: Date(timeIntervalSince1970: 1_000_000_000),
            source: .localIndex
        )
        var results = SearchResultSet()
        results.replace([spotlight], source: .spotlight)

        results.replace([local], source: .localIndex)

        XCTAssertEqual(results.allRecords, [local])
    }

    func testOutputIsDeterministicAcrossSourceAndInputOrder() {
        let spotlightA = record("/资料/Z-Spotlight.pdf", source: .spotlight, offset: 10)
        let spotlightB = record("/资料/A-Spotlight.pdf", source: .spotlight, offset: 20)
        let localA = record("/资料/Z-Local.pdf", source: .localIndex, offset: 30)
        let localB = record("/资料/A-Local.pdf", source: .localIndex, offset: 40)

        var spotlightFirst = SearchResultSet()
        spotlightFirst.replace([spotlightA, spotlightB], source: .spotlight)
        spotlightFirst.replace([localA, localB], source: .localIndex)

        var localFirst = SearchResultSet()
        localFirst.replace([localB, localA], source: .localIndex)
        localFirst.replace([spotlightB, spotlightA], source: .spotlight)

        XCTAssertEqual(spotlightFirst.allRecords, localFirst.allRecords)
    }

    func testClearAllRemovesEverySource() {
        var results = SearchResultSet()
        results.replace(
            [record("/资料/Spotlight.pdf", source: .spotlight, offset: 20)],
            source: .spotlight
        )
        results.replace(
            [record("/资料/Local.pdf", source: .localIndex, offset: 10)],
            source: .localIndex
        )

        results.clearAll()

        XCTAssertTrue(results.allRecords.isEmpty)
    }

    private func record(
        _ path: String,
        source: FileRecordSource,
        offset: TimeInterval
    ) -> FileRecord {
        FileRecord(
            path: path,
            lastUsedAt: Date(timeIntervalSince1970: 2_000_000_000 + offset),
            source: source
        )
    }
}
