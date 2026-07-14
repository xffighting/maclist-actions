import Foundation
import XCTest
@testable import MacListCore

final class MacListCoreTests: XCTestCase {
    func testIndexerIncludesOnlyRegularFilesInsideAuthorizedRoot() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let outside = sandbox.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let allowed = root.appendingPathComponent("Quarterly Plan.pdf")
        let hidden = root.appendingPathComponent(".private.txt")
        let outsideFile = outside.appendingPathComponent("outside.txt")
        try Data("TOP_SECRET_DOCUMENT_BODY".utf8).write(to: allowed)
        try Data("hidden".utf8).write(to: hidden)
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("outside-link.txt"),
            withDestinationURL: outsideFile
        )

        let roots = try AuthorizedRoot.authorize(paths: [root.path])
        XCTAssertTrue(roots[0].contains(allowed))
        let report = FileIndexer().buildSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(report.snapshot.roots, [roots[0].path])
        XCTAssertEqual(
            report.snapshot.files.map(\.path),
            [PathScope.canonicalPath(allowed.path)]
        )
        XCTAssertGreaterThanOrEqual(report.skippedCount, 1)

        let storeURL = sandbox.appendingPathComponent("store/index.json")
        let store = IndexStore(url: storeURL, directoryPolicy: .privateAppDirectory)
        try store.save(report.snapshot)
        let storedJSON = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertFalse(storedJSON.contains("TOP_SECRET_DOCUMENT_BODY"))
    }

    func testAuthorizationRejectsRelativeAndFilePaths() throws {
        do {
            _ = try AuthorizedRoot(path: "Documents")
            XCTFail("Expected a relative-path authorization failure")
        } catch {
            XCTAssertEqual(error as? RootAuthorizationError, .relativePath("Documents"))
        }

        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let file = sandbox.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        do {
            _ = try AuthorizedRoot(path: file.path)
            XCTFail("Expected a file-path authorization failure")
        } catch {
            XCTAssertEqual(
                error as? RootAuthorizationError,
                .notDirectory(PathScope.canonicalPath(file.path))
            )
        }
    }

    func testFuzzyRankingPrefersFilenameOverPathAndIsDeterministic() {
        let files = [
            IndexedFile(path: "/tmp/Finance/quarter.txt", name: "quarter.txt"),
            IndexedFile(path: "/tmp/quarter/notes.txt", name: "notes.txt"),
            IndexedFile(path: "/tmp/Quarterly Plan.pdf", name: "Quarterly Plan.pdf"),
            IndexedFile(path: "/tmp/Quarterly Review.pdf", name: "Quarterly Review.pdf")
        ]

        let matches = FuzzySearch.search("quart", in: files, limit: 10)

        XCTAssertEqual(matches.map(\.file.name), [
            "quarter.txt",
            "Quarterly Plan.pdf",
            "Quarterly Review.pdf",
            "notes.txt"
        ])
        XCTAssertEqual(matches.last?.matchedOn, .path)
        XCTAssertEqual(FuzzySearch.search("qtp", in: files).first?.file.name, "Quarterly Plan.pdf")
    }

    func testShortChineseAndLatinQueriesDoNotRequireThreeCharacters() {
        let files = [
            IndexedFile(path: "/tmp/客户/报价单.xlsx", name: "报价单.xlsx"),
            IndexedFile(path: "/tmp/客户/合同.pdf", name: "合同.pdf"),
            IndexedFile(path: "/tmp/客户/QA.txt", name: "QA.txt")
        ]

        XCTAssertEqual(FuzzySearch.search("报价", in: files).first?.file.name, "报价单.xlsx")
        XCTAssertEqual(FuzzySearch.search("qa", in: files).first?.file.name, "QA.txt")
    }

    func testStoreRoundTripsMetadataWithPrivatePermissionsAndNoDocumentBody() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let storeURL = sandbox
            .appendingPathComponent("private-index", isDirectory: true)
            .appendingPathComponent("index.json")
        let store = IndexStore(url: storeURL, directoryPolicy: .privateAppDirectory)
        let snapshot = IndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: ["/tmp/Authorized"],
            files: [IndexedFile(
                path: "/tmp/Authorized/Quarterly Plan.pdf",
                modifiedAt: Date(timeIntervalSince1970: 1_699_999_000)
            )]
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertEqual(try store.permissions(at: storeURL) & 0o777, 0o600)
        XCTAssertEqual(try store.permissions(at: storeURL.deletingLastPathComponent()) & 0o777, 0o700)
    }

    func testDoctorRejectsEntriesOutsideStoredRootBoundary() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = IndexStore(
            url: sandbox.appendingPathComponent("store/index.json"),
            directoryPolicy: .privateAppDirectory
        )
        try store.save(IndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: [root.path],
            files: [IndexedFile(path: sandbox.appendingPathComponent("outside.txt").path)]
        ))

        let report = Doctor(store: store).run()

        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(report.checks.first(where: { $0.name == "scope-boundary" })?.status, .fail)
    }

    func testIndexerStopsAtConfiguredLimit() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        for name in ["a.txt", "b.txt", "c.txt"] {
            try Data(name.utf8).write(to: sandbox.appendingPathComponent(name))
        }
        let roots = try AuthorizedRoot.authorize(paths: [sandbox.path])

        let report = FileIndexer(options: FileIndexingOptions(maximumFiles: 2))
            .buildSnapshot(roots: roots, generatedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(report.snapshot.files.count, 2)
        XCTAssertTrue(report.reachedLimit)
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacListCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
