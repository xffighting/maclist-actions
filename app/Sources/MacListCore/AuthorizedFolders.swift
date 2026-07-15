import Foundation
import Darwin

public enum AuthorizedFolderBookmarkError: Error, Equatable {
    case invalidFolder
    case unreadableFolder
    case invalidBookmark
    case staleBookmark
}

public struct AuthorizedFolderBookmark: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let pathHint: String
    public let bookmarkData: Data
    public let createdAt: Date

    public init(
        id: UUID,
        displayName: String,
        pathHint: String,
        bookmarkData: Data,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.pathHint = pathHint
        self.bookmarkData = bookmarkData
        let milliseconds = (createdAt.timeIntervalSince1970 * 1_000).rounded(.towardZero)
        self.createdAt = Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    public static func create(
        for folder: URL,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> AuthorizedFolderBookmark {
        let canonicalFolder = folder.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalFolder.isFileURL,
              (canonicalFolder.path as NSString).isAbsolutePath else {
            throw AuthorizedFolderBookmarkError.invalidFolder
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: canonicalFolder.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw AuthorizedFolderBookmarkError.invalidFolder
        }
        guard fileManager.isReadableFile(atPath: canonicalFolder.path) else {
            throw AuthorizedFolderBookmarkError.unreadableFolder
        }

        let data = try canonicalFolder.bookmarkData(
            options: [.withoutImplicitSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard !data.isEmpty else {
            throw AuthorizedFolderBookmarkError.invalidBookmark
        }
        return AuthorizedFolderBookmark(
            id: id,
            displayName: canonicalFolder.lastPathComponent,
            pathHint: canonicalFolder.path,
            bookmarkData: data,
            createdAt: createdAt
        )
    }

    public func resolve(fileManager: FileManager = .default) throws -> URL {
        guard !bookmarkData.isEmpty else {
            throw AuthorizedFolderBookmarkError.invalidBookmark
        }
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else {
            throw AuthorizedFolderBookmarkError.staleBookmark
        }
        let canonicalFolder = resolved.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalFolder.isFileURL,
              (canonicalFolder.path as NSString).isAbsolutePath else {
            throw AuthorizedFolderBookmarkError.invalidBookmark
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: canonicalFolder.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw AuthorizedFolderBookmarkError.invalidFolder
        }
        guard fileManager.isReadableFile(atPath: canonicalFolder.path) else {
            throw AuthorizedFolderBookmarkError.unreadableFolder
        }
        return canonicalFolder
    }
}

public enum AuthorizedFolderStoreError: Error, Equatable {
    case notFound
    case unsupportedFormat(Int)
    case tooLarge
    case insecureStore
    case invalidData
}

public struct AuthorizedFolderStoreLimits: Equatable, Sendable {
    public let maximumBytes: Int
    public let maximumFolders: Int
    public let maximumBookmarkBytes: Int

    public init(
        maximumBytes: Int = 8 * 1_024 * 1_024,
        maximumFolders: Int = 128,
        maximumBookmarkBytes: Int = 1_024 * 1_024
    ) {
        self.maximumBytes = max(1, maximumBytes)
        self.maximumFolders = max(1, maximumFolders)
        self.maximumBookmarkBytes = max(1, maximumBookmarkBytes)
    }
}

public struct AuthorizedFolderSet: Equatable, Sendable {
    public let revision: UUID
    public let folders: [AuthorizedFolderBookmark]

    public init(
        revision: UUID = UUID(),
        folders: [AuthorizedFolderBookmark]
    ) {
        self.revision = revision
        self.folders = folders
    }
}

private struct AuthorizedFolderStoreEnvelope: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let revision: UUID
    let folders: [AuthorizedFolderBookmark]

    init(
        formatVersion: Int = AuthorizedFolderStoreEnvelope.currentFormatVersion,
        authorization: AuthorizedFolderSet
    ) {
        self.formatVersion = formatVersion
        revision = authorization.revision
        folders = authorization.folders
    }

    var authorization: AuthorizedFolderSet {
        AuthorizedFolderSet(revision: revision, folders: folders)
    }
}

public final class AuthorizedFolderStore: @unchecked Sendable {
    public let url: URL
    private let fileManager: FileManager
    private let limits: AuthorizedFolderStoreLimits
    private let lock = NSLock()

    public init(
        url: URL,
        limits: AuthorizedFolderStoreLimits = AuthorizedFolderStoreLimits(),
        fileManager: FileManager = .default
    ) {
        self.url = url.standardizedFileURL
        self.limits = limits
        self.fileManager = fileManager
    }

    public static func defaultURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/MacList", isDirectory: true)
            .appendingPathComponent("authorized-folders.json", isDirectory: false)
    }

    public func save(_ folders: [AuthorizedFolderBookmark]) throws {
        try save(AuthorizedFolderSet(folders: folders))
    }

    public func save(_ authorization: AuthorizedFolderSet) throws {
        lock.lock()
        defer { lock.unlock() }
        try validate(authorization.folders, resolveBookmarks: true)
        try prepareDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(
            AuthorizedFolderStoreEnvelope(authorization: authorization)
        )
        guard data.count <= limits.maximumBytes else {
            throw AuthorizedFolderStoreError.tooLarge
        }
        try writePrivately(data)
    }

    public func load() throws -> [AuthorizedFolderBookmark] {
        try loadSet().folders
    }

    public func loadSet() throws -> AuthorizedFolderSet {
        lock.lock()
        defer { lock.unlock() }
        return try loadSetUnlocked()
    }

    public func loadIfPresent() throws -> [AuthorizedFolderBookmark]? {
        try loadSetIfPresent()?.folders
    }

    public func loadSetIfPresent() throws -> AuthorizedFolderSet? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try loadSetUnlocked()
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for child in children ?? []
        where child.lastPathComponent.hasPrefix(".authorized-folders-") {
            try? fileManager.removeItem(at: child)
        }
    }

    private func loadSetUnlocked() throws -> AuthorizedFolderSet {
        guard fileManager.fileExists(atPath: url.path) else {
            throw AuthorizedFolderStoreError.notFound
        }
        try validateOwnershipAndPermissions()
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else {
            throw AuthorizedFolderStoreError.insecureStore
        }
        guard let fileSize = values.fileSize else {
            throw AuthorizedFolderStoreError.invalidData
        }
        guard fileSize > 0 else { throw AuthorizedFolderStoreError.invalidData }
        guard fileSize <= limits.maximumBytes else {
            throw AuthorizedFolderStoreError.tooLarge
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty else { throw AuthorizedFolderStoreError.invalidData }
        guard data.count <= limits.maximumBytes else {
            throw AuthorizedFolderStoreError.tooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope: AuthorizedFolderStoreEnvelope
        do {
            envelope = try decoder.decode(AuthorizedFolderStoreEnvelope.self, from: data)
        } catch {
            throw AuthorizedFolderStoreError.invalidData
        }
        guard envelope.formatVersion == AuthorizedFolderStoreEnvelope.currentFormatVersion else {
            throw AuthorizedFolderStoreError.unsupportedFormat(envelope.formatVersion)
        }
        try validate(envelope.folders, resolveBookmarks: true)
        return envelope.authorization
    }

    private func validate(
        _ folders: [AuthorizedFolderBookmark],
        resolveBookmarks: Bool
    ) throws {
        guard folders.count <= limits.maximumFolders else {
            throw AuthorizedFolderStoreError.tooLarge
        }
        var identifiers = Set<UUID>()
        for folder in folders {
            guard identifiers.insert(folder.id).inserted,
                  !folder.displayName.isEmpty,
                  folder.displayName.utf8.count <= 1_024,
                  !folder.pathHint.isEmpty,
                  folder.pathHint.utf8.count <= 16_384,
                  (folder.pathHint as NSString).isAbsolutePath,
                  !folder.bookmarkData.isEmpty else {
                throw AuthorizedFolderStoreError.invalidData
            }
            guard folder.bookmarkData.count <= limits.maximumBookmarkBytes else {
                throw AuthorizedFolderStoreError.tooLarge
            }
            if resolveBookmarks {
                do {
                    _ = try folder.resolve(fileManager: fileManager)
                } catch {
                    throw AuthorizedFolderStoreError.invalidData
                }
            }
        }
    }

    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        )
        if exists, !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists)
        }
        if !exists {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw AuthorizedFolderStoreError.insecureStore
        }
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        guard owner == geteuid() else {
            throw AuthorizedFolderStoreError.insecureStore
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private func writePrivately(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".authorized-folders-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func validateOwnershipAndPermissions() throws {
        let fileAttributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileOwner = (fileAttributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let filePermissions = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard fileOwner == geteuid(), filePermissions & 0o077 == 0 else {
            throw AuthorizedFolderStoreError.insecureStore
        }

        let directory = url.deletingLastPathComponent()
        let directoryValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        let directoryAttributes = try fileManager.attributesOfItem(atPath: directory.path)
        let directoryOwner = (directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let directoryPermissions =
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard directoryValues.isSymbolicLink != true,
              directoryOwner == geteuid(),
              directoryPermissions & 0o077 == 0 else {
            throw AuthorizedFolderStoreError.insecureStore
        }
    }
}
