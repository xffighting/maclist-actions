import Foundation
import XCTest
@testable import MacListCore

final class LocalIndexTests: XCTestCase {
    func testParentCustomerFolderMatchesWhenFilenameDoesNotContainCustomerName() {
        let path = "/Volumes/客户资料/远航工业/合同归档/最终版本.pdf"
        let snapshot = LocalIndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: ["/Volumes/客户资料"],
            entries: [
                LocalIndexEntry(
                    path: path,
                    displayName: "最终版本.pdf",
                    modifiedAt: Date(timeIntervalSince1970: 1_699_999_000)
                )
            ]
        )

        let matches = LocalIndexProvider(snapshot: snapshot)
            .matchingFiles("远航工业", limit: 10)

        XCTAssertEqual(matches.map(\.path), [path])
    }

    func testMultipleCustomerAndProjectTokensCanMatchAcrossParentPathSegments() {
        let matchingPath = "/Volumes/客户资料/远航工业/阿曼阀门升级/技术附件/最终清单.xlsx"
        let unrelatedPath = "/Volumes/客户资料/海星能源/宁波扩建/技术附件/最终清单.xlsx"
        let snapshot = LocalIndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: ["/Volumes/客户资料"],
            entries: [
                LocalIndexEntry(
                    path: matchingPath,
                    displayName: "最终清单.xlsx",
                    modifiedAt: Date(timeIntervalSince1970: 1_699_999_000)
                ),
                LocalIndexEntry(
                    path: unrelatedPath,
                    displayName: "最终清单.xlsx",
                    modifiedAt: Date(timeIntervalSince1970: 1_699_998_000)
                )
            ]
        )

        let matches = LocalIndexProvider(snapshot: snapshot)
            .matchingFiles("远航 阿曼升级", limit: 10)

        XCTAssertEqual(matches.map(\.path), [matchingPath])
    }

    func testEmptySnapshotReturnsNoMatches() {
        let snapshot = LocalIndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: [],
            entries: []
        )

        XCTAssertTrue(
            LocalIndexProvider(snapshot: snapshot)
                .matchingFiles("任意客户 任意项目", limit: 10)
                .isEmpty
        )
    }

    func testDefaultProviderStartsEmpty() {
        let provider = LocalIndexProvider()

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertTrue(provider.recentFiles().isEmpty)
        XCTAssertTrue(provider.matchingFiles("任意客户", limit: 10).isEmpty)
    }

    func testIndexerOnlyIndexesRegularFilesInsideAuthorizedRootsAndSkipsHiddenSymlinksAndPackages() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let outside = sandbox.appendingPathComponent("Outside", isDirectory: true)
        let nested = root.appendingPathComponent("远航工业/阿曼阀门升级", isDirectory: true)
        let package = root.appendingPathComponent("Archived.app", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let topLevelFile = root.appendingPathComponent("合同.pdf")
        let nestedFile = nested.appendingPathComponent("最终清单.xlsx")
        let hiddenFile = root.appendingPathComponent(".客户密码.txt")
        let packageFile = package.appendingPathComponent("Contents.txt")
        let outsideFile = outside.appendingPathComponent("outside.txt")
        try Data("contract".utf8).write(to: topLevelFile)
        try Data("list".utf8).write(to: nestedFile)
        try Data("hidden".utf8).write(to: hiddenFile)
        try Data("package".utf8).write(to: packageFile)
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("outside-link.txt"),
            withDestinationURL: outsideFile
        )

        let report = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let canonicalRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertEqual(report.snapshot.roots, [canonicalRootPath])
        XCTAssertEqual(
            Set(report.snapshot.entries.map(\.path)),
            Set([
                topLevelFile.resolvingSymlinksInPath().standardizedFileURL.path,
                nestedFile.resolvingSymlinksInPath().standardizedFileURL.path
            ])
        )
        XCTAssertTrue(
            report.snapshot.entries.allSatisfy {
                $0.path.hasPrefix(canonicalRootPath + "/")
            }
        )
        XCTAssertTrue(report.snapshot.isComplete)
        XCTAssertEqual(report.accessErrorCount, 0)
    }

    func testIndexerDoesNotFollowDirectorySymlinkOutsideAuthorizedRoot() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let outside = sandbox.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let allowedFile = root.appendingPathComponent("allowed.txt")
        let outsideFile = outside.appendingPathComponent("must-not-be-indexed.txt")
        try Data("allowed".utf8).write(to: allowedFile)
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-outside", isDirectory: true),
            withDestinationURL: outside
        )

        let report = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(
            report.snapshot.entries.map(\.path),
            [allowedFile.resolvingSymlinksInPath().standardizedFileURL.path]
        )
        let canonicalOutsidePath = outsideFile.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertFalse(report.snapshot.entries.contains { $0.path == canonicalOutsidePath })
    }

    func testChildDirectoryEnumerationErrorKeepsSafeResultsButMarksSnapshotIncomplete() throws {
        let sandbox = try makeSandbox()
        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let blockedChild = root.appendingPathComponent("BlockedProject", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: blockedChild.path
            )
            try? FileManager.default.removeItem(at: sandbox)
        }
        try FileManager.default.createDirectory(
            at: blockedChild,
            withIntermediateDirectories: true
        )
        let safeFile = root.appendingPathComponent("visible.pdf")
        try Data("safe".utf8).write(to: safeFile)
        try Data("blocked".utf8).write(
            to: blockedChild.appendingPathComponent("blocked.pdf")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o000)],
            ofItemAtPath: blockedChild.path
        )

        let report = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(
            report.snapshot.entries.map(\.path),
            [safeFile.resolvingSymlinksInPath().standardizedFileURL.path]
        )
        XCTAssertGreaterThan(report.accessErrorCount, 0)
        XCTAssertFalse(report.snapshot.isComplete)
    }

    func testResourceMetadataAccessErrorIsDistinctFromPolicySkipAndMakesSnapshotIncomplete() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safeFile = root.appendingPathComponent("safe.txt")
        let deniedFile = root.appendingPathComponent("metadata-denied.txt")
        try Data("safe".utf8).write(to: safeFile)
        try Data("denied".utf8).write(to: deniedFile)

        let report = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false),
            resourceValueLoader: { candidate, keys in
                if candidate.lastPathComponent == deniedFile.lastPathComponent,
                   keys.contains(.isRegularFileKey) {
                    throw SyntheticMetadataError.denied
                }
                return try candidate.resourceValues(forKeys: keys)
            }
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(
            report.snapshot.entries.map(\.path),
            [safeFile.resolvingSymlinksInPath().standardizedFileURL.path]
        )
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.accessErrorCount, 1)
        XCTAssertFalse(report.snapshot.isComplete)
    }

    func testStoreLoadFailsClosedWhenEntryFallsOutsideDeclaredRoots() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let outsidePath = sandbox.appendingPathComponent("Authorized-escape/outside.txt").path
        let storeURL = sandbox.appendingPathComponent("store/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [root.path],
                entries: [LocalIndexEntry(path: outsidePath, displayName: "outside.txt")]
            ),
            to: storeURL
        )

        XCTAssertThrowsError(try LocalIndexStore(url: storeURL).load()) { error in
            XCTAssertEqual(error as? LocalIndexStoreError, .invalidScope)
        }
    }

    func testStoreRejectsPayloadBeyondConfiguredByteLimitBeforeDecoding() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let storeURL = sandbox.appendingPathComponent("store/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [root.path],
                entries: [
                    LocalIndexEntry(
                        path: root.appendingPathComponent("a-long-enough-filename-to-exceed-the-test-limit.pdf").path,
                        displayName: "a-long-enough-filename-to-exceed-the-test-limit.pdf"
                    )
                ]
            ),
            to: storeURL
        )
        XCTAssertGreaterThan(try Data(contentsOf: storeURL).count, 64)
        let store = LocalIndexStore(
            url: storeURL,
            limits: LocalIndexStoreLimits(maximumBytes: 64, maximumEntries: 10)
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LocalIndexStoreError, .tooLarge)
        }
    }

    func testStoreRejectsSnapshotBeyondConfiguredEntryLimit() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        let storeURL = sandbox.appendingPathComponent("store/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [root.path],
                entries: [
                    LocalIndexEntry(path: root.appendingPathComponent("one.pdf").path),
                    LocalIndexEntry(path: root.appendingPathComponent("two.pdf").path)
                ]
            ),
            to: storeURL
        )
        let store = LocalIndexStore(
            url: storeURL,
            limits: LocalIndexStoreLimits(maximumBytes: 1_048_576, maximumEntries: 1)
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LocalIndexStoreError, .tooLarge)
        }
    }

    func testStoreRoundTripsPrivateMetadataWithoutPersistingDocumentContentsAndCanClear() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Authorized", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceFile = root.appendingPathComponent("远航项目合同.txt")
        let privateDocumentBody = "MACLIST_PRIVATE_DOCUMENT_BODY_MUST_NOT_BE_INDEXED"
        try Data(privateDocumentBody.utf8).write(to: sourceFile)

        let snapshot = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ).snapshot
        let storeURL = sandbox
            .appendingPathComponent("private-index", isDirectory: true)
            .appendingPathComponent("index.json")
        let store = LocalIndexStore(url: storeURL)

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertEqual(try permissions(at: storeURL) & 0o777, 0o600)
        XCTAssertEqual(try permissions(at: storeURL.deletingLastPathComponent()) & 0o777, 0o700)
        XCTAssertFalse(
            try String(contentsOf: storeURL, encoding: .utf8)
                .contains(privateDocumentBody)
        )

        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacListLocalIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private func writeSnapshot(_ snapshot: LocalIndexSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(snapshot).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

private enum SyntheticMetadataError: Error {
    case denied
}
