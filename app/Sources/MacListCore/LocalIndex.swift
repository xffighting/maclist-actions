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
    // Version 2 invalidates snapshots produced before access failures were
    // represented in the completeness semantics. Version 1 may silently omit
    // unreadable subtrees, so it must be rebuilt instead of reused as ready.
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public let generatedAt: Date
    public let roots: [String]
    public let entries: [LocalIndexEntry]
    public let rootRevision: UUID?
    public let isComplete: Bool

    public init(
        formatVersion: Int = LocalIndexSnapshot.currentFormatVersion,
        generatedAt: Date,
        roots: [String],
        entries: [LocalIndexEntry],
        rootRevision: UUID? = nil,
        isComplete: Bool = true
    ) {
        self.formatVersion = formatVersion
        let milliseconds = (generatedAt.timeIntervalSince1970 * 1_000).rounded(.towardZero)
        self.generatedAt = Date(timeIntervalSince1970: milliseconds / 1_000)
        self.roots = roots
        self.entries = entries
        self.rootRevision = rootRevision
        self.isComplete = isComplete
    }

    public static var empty: LocalIndexSnapshot {
        LocalIndexSnapshot(generatedAt: .distantPast, roots: [], entries: [])
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case generatedAt
        case roots
        case entries
        case rootRevision
        case isComplete
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        roots = try container.decode([String].self, forKey: .roots)
        entries = try container.decode([LocalIndexEntry].self, forKey: .entries)
        rootRevision = try container.decodeIfPresent(UUID.self, forKey: .rootRevision)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(roots, forKey: .roots)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(rootRevision, forKey: .rootRevision)
        try container.encode(isComplete, forKey: .isComplete)
    }
}

public struct LocalIndexingReport: Sendable {
    public let snapshot: LocalIndexSnapshot
    public let skippedCount: Int
    public let inaccessibleRootCount: Int
    public let accessErrorCount: Int
    public let reachedLimit: Bool
    public let reachedVisitLimit: Bool
    public let wasCancelled: Bool

    public init(
        snapshot: LocalIndexSnapshot,
        skippedCount: Int,
        inaccessibleRootCount: Int,
        reachedLimit: Bool,
        reachedVisitLimit: Bool = false,
        accessErrorCount: Int = 0,
        wasCancelled: Bool = false
    ) {
        self.snapshot = snapshot
        self.skippedCount = skippedCount
        self.inaccessibleRootCount = inaccessibleRootCount
        self.accessErrorCount = accessErrorCount
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
    private let resourceValueLoader: (URL, Set<URLResourceKey>) throws -> URLResourceValues

    public init(
        fileManager: FileManager = .default,
        options: LocalFileIndexingOptions = LocalFileIndexingOptions()
    ) {
        self.fileManager = fileManager
        self.options = options
        resourceValueLoader = { url, keys in
            try url.resourceValues(forKeys: keys)
        }
    }

    init(
        fileManager: FileManager = .default,
        options: LocalFileIndexingOptions = LocalFileIndexingOptions(),
        resourceValueLoader: @escaping (
            URL,
            Set<URLResourceKey>
        ) throws -> URLResourceValues
    ) {
        self.fileManager = fileManager
        self.options = options
        self.resourceValueLoader = resourceValueLoader
    }

    public func buildSnapshot(
        roots: [URL],
        generatedAt: Date = Date(),
        rootRevision: UUID? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> LocalIndexingReport {
        let normalizedRoots = normalizedReadableRoots(roots)
        let authorizedRoots = normalizedRoots.urls
        var entriesByPath: [String: LocalIndexEntry] = [:]
        var skippedCount = 0
        var accessErrorCount = 0
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
                errorHandler: { _, _ in
                    accessErrorCount += 1
                    return true
                }
            ) else {
                accessErrorCount += 1
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
                    let values = try resourceValueLoader(candidate, requiredResourceKeys)
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
                    let modifiedAt: Date?
                    do {
                        modifiedAt = try resourceValueLoader(
                            candidate,
                            [.contentModificationDateKey]
                        ).contentModificationDate
                    } catch {
                        accessErrorCount += 1
                        modifiedAt = nil
                    }
                    entriesByPath[canonicalURL.path] = LocalIndexEntry(
                        path: canonicalURL.path,
                        displayName: canonicalURL.lastPathComponent,
                        modifiedAt: modifiedAt
                    )
                } catch {
                    accessErrorCount += 1
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
                entries: entries,
                rootRevision: rootRevision,
                isComplete: !reachedLimit
                    && !reachedVisitLimit
                    && normalizedRoots.inaccessibleCount == 0
                    && accessErrorCount == 0
            ),
            skippedCount: skippedCount,
            inaccessibleRootCount: normalizedRoots.inaccessibleCount,
            reachedLimit: reachedLimit,
            reachedVisitLimit: reachedVisitLimit,
            accessErrorCount: accessErrorCount,
            wasCancelled: wasCancelled
        )
    }

    private func normalizedReadableRoots(
        _ roots: [URL]
    ) -> (urls: [URL], inaccessibleCount: Int) {
        var seen = Set<String>()
        var inaccessibleCount = 0
        let readableRoots: [URL] = roots.compactMap { root -> URL? in
            let canonical = LocalIndexPathScope.canonicalURL(root)
            guard canonical.isFileURL,
                  canonical.path.hasPrefix("/") else {
                inaccessibleCount += 1
                return nil
            }
            guard seen.insert(canonical.path).inserted else { return nil }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: canonical.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue,
            fileManager.isReadableFile(atPath: canonical.path),
            fileManager.isExecutableFile(atPath: canonical.path) else {
                inaccessibleCount += 1
                return nil
            }
            return canonical
        }
        let sortedRoots = readableRoots.sorted { $0.path < $1.path }
        let minimized = sortedRoots.reduce(into: [URL]()) { accepted, candidate in
            guard !accepted.contains(where: {
                LocalIndexPathScope.contains(path: candidate.path, root: $0.path)
            }) else { return }
            accepted.append(candidate)
        }
        return (minimized, inaccessibleCount)
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
        try validateOwnershipAndPermissions()
        let data = try readPrivately()
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
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        guard owner == geteuid() else {
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
        guard owner == geteuid(), permissions & 0o077 == 0 else {
            throw LocalIndexStoreError.insecureStore
        }

        let directory = url.deletingLastPathComponent()
        let directoryValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        let directoryAttributes = try fileManager.attributesOfItem(atPath: directory.path)
        let directoryOwner =
            (directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let directoryPermissions =
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard directoryValues.isSymbolicLink != true,
              directoryOwner == geteuid(),
              directoryPermissions & 0o077 == 0 else {
            throw LocalIndexStoreError.insecureStore
        }
    }

    private func readPrivately() throws -> Data {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { throw LocalIndexStoreError.notFound }
            throw LocalIndexStoreError.insecureStore
        }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            Darwin.close(descriptor)
            throw LocalIndexStoreError.insecureStore
        }
        guard information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              Int(information.st_mode & 0o077) == 0 else {
            Darwin.close(descriptor)
            throw LocalIndexStoreError.insecureStore
        }
        guard information.st_size >= 0,
              UInt64(information.st_size) <= UInt64(limits.maximumBytes) else {
            Darwin.close(descriptor)
            throw LocalIndexStoreError.tooLarge
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.read(upToCount: limits.maximumBytes + 1) ?? Data()
            try handle.close()
            guard data.count <= limits.maximumBytes else {
                throw LocalIndexStoreError.tooLarge
            }
            return data
        } catch {
            try? handle.close()
            throw error
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
