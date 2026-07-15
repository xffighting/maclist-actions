import Foundation

enum SearchResultSetSmoke {
    static func run() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let spotlightOnly = FileRecord(
            path: "/Volumes/客户资料/远航工业/Spotlight-合同.pdf",
            lastUsedAt: now,
            source: .spotlight
        )
        let sharedSpotlight = FileRecord(
            path: "/Volumes/客户资料/远航工业/阿曼项目/最终清单.xlsx",
            displayName: "Spotlight 最终清单.xlsx",
            lastUsedAt: now,
            source: .spotlight
        )
        let sharedLocal = FileRecord(
            path: sharedSpotlight.path,
            displayName: "本地索引 最终清单.xlsx",
            lastUsedAt: now.addingTimeInterval(-3_600),
            source: .localIndex
        )

        var results = SearchResultSet()
        results.replace([spotlightOnly, sharedSpotlight], source: .spotlight)
        results.replace([sharedLocal], source: .localIndex)

        precondition(results.allRecords.count == 2)
        precondition(
            results.allRecords.first { $0.path == sharedSpotlight.path }?.source == .localIndex
        )

        results.replace([], source: .spotlight)
        precondition(results.allRecords == [sharedLocal])
        print("search-result-set: ok")
    }
}
