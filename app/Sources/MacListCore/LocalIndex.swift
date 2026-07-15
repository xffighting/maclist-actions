import Foundation
import Darwin

private enum LocalIndexPathScope {
    static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    static func canonicalPath(_ path: String) -> String {
        canonicalURL(URL(fileURLWithPath: path)).path
    }

    static func contains(path: String, root: String) -> Bool {
        let candidate = canonicalPath(path)
        let boundary = canonicalPath(root)
        return candidate == boundary || candidate.hasPrefix(boundary + "/")
    }
}

public struct LocalIndexEntry: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public let displayName: String
    public let modifiedAt: Date?

    public var id: String { path }

    public init(
        path: String,
        displayName: String? = nil,
        modifiedAt: Date? = nil
    ) {
        let canonicalPath = LocalIndexPathScope.canonicalPath(path)
        self.path = canonicalPath
        self.displayName = displayName
            ?? URL(fileURLWithPath: canonicalPath).lastPathComponent
        self.modifiedAt = modifiedAt.map { date in
            let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.towardZero)
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
    }
}

public struct LocalIndexSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let generatedAt: Date
    public let roots: [String]
    public let entries: [LocalIndexEntry]

    public init(
        formatVersion: Int = LocalIndexSnapshot.currentFormatVersion,
        generatedAt: Date,
        roots: [String],
        entries: [LocalIndexEntry]
    ) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.roots = roots
        self.entries = entries
    }

    public static var empty: LocalIndexSnapshot {
        LocalIndexSnapshot(generatedAt: .distantPast, roots: [], entries: [])
    }
}

public struct LocalIndexingReport: Sendable {
    public let snapshot: LocalIndexSnapshot
    public let skippedCount: Int
    public let inaccessibleRootCount: Int
    public let reachedLimit: Bool
    public let reachedVisitLimit: Bool
    public let wasCancelled: Bool

    public init(
        snapshot: LocalIndexSnapshot,
        skippedCount: Int,
        inaccessibleRootCount: Int,
        reachedLimit: Bool,
        reachedVisitLimit: Bool = false,
        wasCancelled: Bool = false
    ) {
        self.snapshot = snapshot
        self.skippedCount = skippedCount
        self.inaccessibleRootCount = inaccessibleRootCount
        self.reachedLimit = reachedLimit
        self.reachedVisitLimit = reachedVisitLimit
        self.wasCancelled = wasCancelled
    }
}

public struct LocalFileIndexingOptions: Equatable, Sendable {
    public let maximumFiles: Int
    public let includeHidden: Bool
    public let maximumVisitedItems: Int
    public let maximumDuration: TimeInterval

    public init(
        maximumFiles: Int = 250_000,
        includeHidden: Bool = false,
        maximumVisitedItems: Int = 1_000_000,
        maximumDuration: TimeInterval = 120
    ) {
        self.maximumFiles = max(1, maximumFiles)
        self.includeHidden = includeHidden
        self.maximumVisitedItems = max(1, maximumVisitedItems)
        self.maximumDuration = max(1, maximumDuration)
    }
}

public final class LocalFileIndexer: @unchecked Sendable {
    private let fileManager: FileManager
    private let options: LocalFileIndexingOptions

    public init(
        fileManager: FileManager = .default,
        options: LocalFileIndexingOptions = LocalFileIndexingOptions()
    ) {
        self.fileManager = fileManager
        self.options = options
    }

    public func buildSnapshot(
        roots: [URL],
        generatedAt: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) -> LocalIndexingReport {
        let authorizedRoots = normalizedReadableRoots(roots)
        var entriesByPath: [String: LocalIndexEntry] = [:]
        var skippedCount = 0
        var reachedLimit = false
        var reachedVisitLimit = false
        var wasCancelled = false
        var visitedItems = 0
        let deadline = Date().addingTimeInterval(options.maximumDuration)

        let requiredResourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey
        ]
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [
            .skipsPackageDescendants
        ]
        if !options.includeHidden {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        rootLoop: for root in authorizedRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(requiredResourceKeys),
                options: enumerationOptions,
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            while let candidate = enumerator.nextObject() as? URL {
                visitedItems += 1
                if isCancelled() {
                    wasCancelled = true
                    break rootLoop
                }
                if visitedItems > options.maximumVisitedItems || Date() >= deadline {
                    reachedVisitLimit = true
                    break rootLoop
                }
                if entriesByPath.count >= options.maximumFiles {
                    reachedLimit = true
                    break rootLoop
                }

                do {
                    let values = try candidate.resourceValues(forKeys: requiredResourceKeys)
                    if values.isSymbolicLink == true {
                        skippedCount += 1
                        if values.isDirectory == true { enumerator.skipDescendants() }
                        continue
                    }
                    if values.isDirectory == true {
                        if values.isPackage == true { enumerator.skipDescendants() }
                        continue
                    }
                    guard values.isRegularFile == true else {
                        skippedCount += 1
                        continue
                    }

                    let canonicalURL = LocalIndexPathScope.canonicalURL(candidate)
                    guard isInside(canonicalURL, root: root) else {
                        skippedCount += 1
                        continue
                    }
                    let modifiedAt = try? candidate.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate
                    entriesByPath[canonicalURL.path] = LocalIndexEntry(
                        path: canonicalURL.path,
                        displayName: canonicalURL.lastPathComponent,
                        modifiedAt: modifiedAt
                    )
                } catch {
                    skippedCount += 1
                }
            }
        }

        let entries = entriesByPath.values.sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameOrder == .orderedSame { return lhs.path < rhs.path }
            return nameOrder == .orderedAscending
        }
        return LocalIndexingReport(
            snapshot: LocalIndexSnapshot(
                generatedAt: generatedAt,
                roots: authorizedRoots.map(\.path),
                entries: entries
            ),
            skippedCount: skippedCount,
            inaccessibleRootCount: max(0, roots.count - authorizedRoots.count),
            reachedLimit: reachedLimit,
            reachedVisitLimit: reachedVisitLimit,
            wasCancelled: wasCancelled
        )
    }

    private func normalizedReadableRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        let readableRoots: [URL] = roots.compactMap { root -> URL? in
            let canonical = LocalIndexPathScope.canonicalURL(root)
            guard canonical.isFileURL,
                  canonical.path.hasPrefix("/"),
                  seen.insert(canonical.path).inserted else {
                return nil
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: canonical.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue,
            fileManager.isReadableFile(atPath: canonical.path) else {
                return nil
            }
            return canonical
        }
        let sortedRoots = readableRoots.sorted { $0.path < $1.path }
        return sortedRoots.reduce(into: [URL]()) { accepted, candidate in
            guard !accepted.contains(where: {
                LocalIndexPathScope.contains(path: candidate.path, root: $0.path)
            }) else { return }
            accepted.append(candidate)
        }
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        LocalIndexPathScope.contains(path: candidate.path, root: root.path)
    }
}

public enum LocalIndexStoreError: Error, Equatable {
    case notFound
    case unsupportedFormat(Int)
    case invalidScope
    case tooLarge
    case insecureStore
}

public struct LocalIndexStoreLimits: Equatable, Sendable {
    public let maximumBytes: Int
    public let maximumEntries: Int
    public let maximumRoots: Int

    public init(
        maximumBytes: Int = 128 * 1_024 * 1_024,
        maximumEntries: Int = 250_000,
        maximumRoots: Int = 128
    ) {
        self.maximumBytes = max(1, maximumBytes)
        self.maximumEntries = max(1, maximumEntries)
        self.maximumRoots = max(1, maximumRoots)
    }
}

public final class LocalIndexStore: @unchecked Sendable {
    public let url: URL
    private let fileManager: FileManager
    private let limits: LocalIndexStoreLimits
    private let lock = NSLock()

    public init(
        url: URL,
        limits: LocalIndexStoreLimits = LocalIndexStoreLimits(),
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
            .appendingPathComponent("local-index.json", isDirectory: false)
    }

    public func save(_ snapshot: LocalIndexSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.entries.count <= limits.maximumEntries,
              snapshot.roots.count <= limits.maximumRoots else {
            throw LocalIndexStoreError.tooLarge
        }
        try validateScope(snapshot)
        try prepareDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        guard data.count <= limits.maximumBytes else {
            throw LocalIndexStoreError.tooLarge
        }
        try writePrivately(data)
    }

    public func load() throws -> LocalIndexSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    private func loadUnlocked() throws -> LocalIndexSnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalIndexStoreError.notFound
        }
        let resourceValues = try url.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard resourceValues.isSymbolicLink != true else {
            throw LocalIndexStoreError.insecureStore
        }
        guard (resourceValues.fileSize ?? 0) <= limits.maximumBytes else {
            throw LocalIndexStoreError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= limits.maximumBytes else {
            throw LocalIndexStoreError.tooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(LocalIndexSnapshot.self, from: data)
        guard snapshot.formatVersion == LocalIndexSnapshot.currentFormatVersion else {
            throw LocalIndexStoreError.unsupportedFormat(snapshot.formatVersion)
        }
        guard snapshot.entries.count <= limits.maximumEntries,
              snapshot.roots.count <= limits.maximumRoots else {
            throw LocalIndexStoreError.tooLarge
        }
        try validateScope(snapshot)
        try validateOwnershipAndPermissions()
        return snapshot
    }

    public func loadIfPresent() throws -> LocalIndexSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try loadUnlocked()
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        let temporaryPrefix = ".local-index-"
        let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for child in children ?? [] where child.lastPathComponent.hasPrefix(temporaryPrefix) {
            try? fileManager.removeItem(at: child)
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
            throw LocalIndexStoreError.insecureStore
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private func writePrivately(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".local-index-\(UUID().uuidString).tmp"
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

    private func validateScope(_ snapshot: LocalIndexSnapshot) throws {
        if snapshot.entries.isEmpty { return }
        let roots = snapshot.roots.map(LocalIndexPathScope.canonicalPath)
        guard !roots.isEmpty,
              roots.allSatisfy({ ($0 as NSString).isAbsolutePath }),
              snapshot.entries.allSatisfy({ entry in
                  roots.contains(where: {
                      LocalIndexPathScope.contains(path: entry.path, root: $0)
                  })
              }) else {
            throw LocalIndexStoreError.invalidScope
        }
    }

    private func validateOwnershipAndPermissions() throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard owner == getuid(), permissions & 0o077 == 0 else {
            throw LocalIndexStoreError.insecureStore
        }
    }
}

public final class LocalIndexProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: LocalIndexSnapshot
    private var records: [FileRecord]

    public init(snapshot: LocalIndexSnapshot = .empty) {
        storedSnapshot = snapshot
        records = Self.makeRecords(from: snapshot)
    }

    public var snapshot: LocalIndexSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    public func replaceSnapshot(_ snapshot: LocalIndexSnapshot) {
        let replacementRecords = Self.makeRecords(from: snapshot)
        lock.lock()
        storedSnapshot = snapshot
        records = replacementRecords
        lock.unlock()
    }

    public func clear() {
        replaceSnapshot(.empty)
    }

    public func recentFiles(limit: Int = 2_000) -> [FileRecord] {
        SearchEngine.search("", in: currentRecords(), limit: limit)
    }

    public func matchingFiles(_ query: String, limit: Int = 600) -> [FileRecord] {
        SearchEngine.search(query, in: currentRecords(), limit: limit)
    }

    private func currentRecords() -> [FileRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private static func makeRecords(from snapshot: LocalIndexSnapshot) -> [FileRecord] {
        snapshot.entries.map { entry in
            FileRecord(
                path: entry.path,
                displayName: entry.displayName,
                lastUsedAt: entry.modifiedAt ?? .distantPast,
                source: .localIndex
            )
        }
    }
}
