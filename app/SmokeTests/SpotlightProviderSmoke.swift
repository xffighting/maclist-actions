import Foundation

enum SpotlightProviderSmoke {
    static func run() throws {
        let homeDirectory = URL(fileURLWithPath: "/tmp/maclist-smoke-home", isDirectory: true)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-mdfind.sh")
        let provider = SpotlightProvider(
            homeDirectory: homeDirectory,
            executableURL: fixture
        )

        let records = try provider.matchingFiles("客户 报价", limit: 10)
        precondition(records.map(\.displayName) == [
            "客户报价单.xlsx",
            "云端报价.pdf",
            "年度报价.xlsx"
        ])
        precondition(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-smoke-home/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        precondition(
            !PrivacyPolicy.shouldInclude(
                path: "/tmp/maclist-smoke-home/Documents/客户报价单.xlsx",
                homeDirectory: homeDirectory
            )
        )
        precondition(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-smoke-home/Library/Mobile Documents/com~apple~CloudDocs/资料/云端报价.pdf",
                homeDirectory: homeDirectory
            )
        )
        precondition(
            PrivacyPolicy.shouldIncludeSpotlightPath(
                path: "/tmp/maclist-smoke-home/Library/CloudStorage/OneDrive/Documents/年度报价.xlsx",
                homeDirectory: homeDirectory
            )
        )

        let limitedRecords = try provider.matchingFiles("报价", limit: 2)
        precondition(limitedRecords.map(\.displayName) == [
            "客户报价单.xlsx",
            "云端报价.pdf"
        ])

        let slowFixture = fixture
            .deletingLastPathComponent()
            .appendingPathComponent("fake-mdfind-slow.sh")
        let slowProvider = SpotlightProvider(
            homeDirectory: homeDirectory,
            executableURL: slowFixture
        )
        let cancellation = SpotlightQueryCancellation()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            cancellation.cancel()
        }
        let cancellationStartedAt = Date()
        let cancelledRecords = try slowProvider.matchingFiles(
            "报价",
            cancellation: cancellation
        )
        precondition(cancelledRecords.isEmpty)
        precondition(Date().timeIntervalSince(cancellationStartedAt) < 2)

        let failureFixture = fixture
            .deletingLastPathComponent()
            .appendingPathComponent("fake-mdfind-failure.sh")
        let failureProvider = SpotlightProvider(
            homeDirectory: homeDirectory,
            executableURL: failureFixture
        )
        do {
            _ = try failureProvider.matchingFiles("报价")
            preconditionFailure("nonzero Spotlight exit must fail")
        } catch SpotlightError.failed(7, let message) {
            precondition(message == "fixture query failure")
        }
        print("spotlight-provider: ok")
    }
}
