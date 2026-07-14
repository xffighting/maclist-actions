import Foundation

enum FuzzySearchSmoke {
    static func run() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let records = [
            FileRecord(
                path: "/Volumes/TestData/客户资料/普通文件.pdf",
                lastUsedAt: now,
                source: .spotlight
            ),
            FileRecord(
                path: "/Volumes/TestData/Documents/Customer-Quotation-2026.xlsx",
                lastUsedAt: now.addingTimeInterval(-3_600),
                source: .spotlight
            ),
            FileRecord(
                path: "/Volumes/TestData/项目/客户报价单.xlsx",
                lastUsedAt: now.addingTimeInterval(-7_200),
                source: .spotlight
            )
        ]

        precondition(SearchEngine.search("客户 报价", in: records, now: now).first?.displayName == "客户报价单.xlsx")
        precondition(SearchEngine.search("ctmr qttn", in: records, now: now).first?.displayName == "Customer-Quotation-2026.xlsx")
        precondition(SearchEngine.search("不存在", in: records, now: now).isEmpty)
        print("fuzzy-search: ok")
    }
}
