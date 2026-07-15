import Foundation
import XCTest
@testable import MacListCore

final class AuthorizedFolderBookmarkTests: XCTestCase {
    func testRegularBookmarkRoundTripsCanonicalFolderAndMetadata() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = sandbox.appendingPathComponent("客户资料", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let bookmark = try AuthorizedFolderBookmark.create(
            for: folder,
            id: id,
            createdAt: createdAt
        )

        let canonicalFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        XCTAssertEqual(bookmark.id, id)
        XCTAssertEqual(bookmark.displayName, folder.lastPathComponent)
        XCTAssertEqual(bookmark.pathHint, canonicalFolder.path)
        XCTAssertFalse(bookmark.bookmarkData.isEmpty)
        XCTAssertEqual(bookmark.createdAt, createdAt)
        XCTAssertEqual(
            try bookmark.resolve().resolvingSymlinksInPath().standardizedFileURL,
            canonicalFolder
        )
    }

    func testStoreRoundTripsBookmarksWithPrivatePermissionsAndCanClear() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = sandbox.appendingPathComponent("远航工业", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try AuthorizedFolderBookmark.create(
            for: folder,
            id: UUID(uuidString: "D4D7E977-374B-420A-A8D5-B0E01968DB58")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let storeURL = sandbox
            .appendingPathComponent("private-bookmarks", isDirectory: true)
            .appendingPathComponent("authorized-folders.json")
        let store = AuthorizedFolderStore(url: storeURL)

        try store.save([bookmark])

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, bookmark.id)
        XCTAssertEqual(loaded[0].displayName, bookmark.displayName)
        XCTAssertEqual(loaded[0].pathHint, bookmark.pathHint)
        XCTAssertEqual(loaded[0].bookmarkData, bookmark.bookmarkData)
        XCTAssertEqual(loaded[0].createdAt, bookmark.createdAt)
        XCTAssertEqual(
            try loaded[0].resolve().resolvingSymlinksInPath().standardizedFileURL,
            folder.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertEqual(try permissions(at: storeURL) & 0o777, 0o600)
        XCTAssertEqual(
            try permissions(at: storeURL.deletingLastPathComponent()) & 0o777,
            0o700
        )

        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testStoreFailsClosedForEmptyOrCorruptPersistedBookmarkData() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let storeURL = sandbox
            .appendingPathComponent("damaged-bookmarks", isDirectory: true)
            .appendingPathComponent("authorized-folders.json")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = AuthorizedFolderStore(url: storeURL)

        try Data().write(to: storeURL, options: .atomic)
        XCTAssertThrowsError(try store.load())

        try Data("not-a-valid-authorized-folder-bookmark".utf8)
            .write(to: storeURL, options: .atomic)
        XCTAssertThrowsError(try store.load())
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacListAuthorizedFolderBookmarkTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}
