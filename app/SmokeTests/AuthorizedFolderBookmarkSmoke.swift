import Foundation

enum AuthorizedFolderBookmarkSmoke {
    static func run() throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent(
                "MacListAuthorizedFolderBookmarkSmoke-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        let folder = sandbox.appendingPathComponent("客户资料", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID(uuidString: "164DB403-E4C8-4037-A035-B3D39EDC250D")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let bookmark = try AuthorizedFolderBookmark.create(
            for: folder,
            id: id,
            createdAt: createdAt
        )
        let canonicalFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFolder = try bookmark.resolve()
            .resolvingSymlinksInPath()
            .standardizedFileURL

        precondition(bookmark.id == id)
        precondition(bookmark.displayName == folder.lastPathComponent)
        precondition(bookmark.pathHint == canonicalFolder.path)
        precondition(!bookmark.bookmarkData.isEmpty)
        precondition(bookmark.createdAt == createdAt)
        precondition(resolvedFolder == canonicalFolder)

        let storeURL = sandbox
            .appendingPathComponent("store", isDirectory: true)
            .appendingPathComponent("authorized-folders.json")
        let store = AuthorizedFolderStore(url: storeURL)
        try store.save([bookmark])

        let loaded = try store.load()
        let loadedResolvedFolder = try loaded[0].resolve()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let fileMode = try permissions(at: storeURL)
        let directoryMode = try permissions(at: storeURL.deletingLastPathComponent())
        precondition(loaded.count == 1)
        precondition(loaded[0].id == bookmark.id)
        precondition(loaded[0].displayName == bookmark.displayName)
        precondition(loaded[0].pathHint == bookmark.pathHint)
        precondition(loaded[0].bookmarkData == bookmark.bookmarkData)
        precondition(loaded[0].createdAt == bookmark.createdAt)
        precondition(loadedResolvedFolder == canonicalFolder)
        precondition(fileMode & 0o777 == 0o600)
        precondition(directoryMode & 0o777 == 0o700)

        try store.clear()
        precondition(!fileManager.fileExists(atPath: storeURL.path))

        try Data().write(to: storeURL, options: .atomic)
        try expectLoadFailure(store)
        try Data("not-a-valid-authorized-folder-bookmark".utf8)
            .write(to: storeURL, options: .atomic)
        try expectLoadFailure(store)
    }

    private static func expectLoadFailure(_ store: AuthorizedFolderStore) throws {
        do {
            _ = try store.load()
            preconditionFailure("empty or corrupt bookmark data must fail closed")
        } catch {
            // Expected: malformed persisted bookmark data must never be trusted.
        }
    }

    private static func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}
