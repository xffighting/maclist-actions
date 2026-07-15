import Foundation

public protocol LocalIndexBuilding: Sendable {
    func buildSnapshot(
        roots: [URL],
        generatedAt: Date,
        rootRevision: UUID,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> LocalIndexingReport
}

extension LocalFileIndexer: LocalIndexBuilding {
    public func buildSnapshot(
        roots: [URL],
        generatedAt: Date,
        rootRevision: UUID,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> LocalIndexingReport {
        buildSnapshot(
            roots: roots,
            generatedAt: generatedAt,
            rootRevision: Optional(rootRevision),
            isCancelled: isCancelled
        )
    }
}

public enum LocalIndexServiceState: Equatable, Sendable {
    case disabled
    case indexing(folderCount: Int)
    case ready(fileCount: Int, folderCount: Int, generatedAt: Date)
    case needsRefresh(folderCount: Int)
    case needsAuthorization
    case failed
}

public actor LocalIndexService {
    public nonisolated let provider: LocalIndexProvider
    public private(set) var state: LocalIndexServiceState = .disabled

    private let authorizedFolderStore: AuthorizedFolderStore
    private let indexStore: LocalIndexStore
    private let indexer: any LocalIndexBuilding
    private let rootPolicy: LocalIndexRootPolicy
    private var generation: UInt64 = 0
    private var runningTask: Task<LocalIndexingReport, Never>?

    public init(
        provider: LocalIndexProvider = LocalIndexProvider(),
        authorizedFolderStore: AuthorizedFolderStore = AuthorizedFolderStore(
            url: AuthorizedFolderStore.defaultURL()
        ),
        indexStore: LocalIndexStore = LocalIndexStore(url: LocalIndexStore.defaultURL()),
        indexer: any LocalIndexBuilding = LocalFileIndexer(),
        rootPolicy: LocalIndexRootPolicy = LocalIndexRootPolicy()
    ) {
        self.provider = provider
        self.authorizedFolderStore = authorizedFolderStore
        self.indexStore = indexStore
        self.indexer = indexer
        self.rootPolicy = rootPolicy
    }

    public func bootstrap() async {
        provider.clear()
        do {
            guard let authorization = try authorizedFolderStore.loadSetIfPresent(),
                  !authorization.folders.isEmpty else {
                state = .disabled
                return
            }
            let authorizedRoots = try resolveAuthorizedRoots(authorization)
            guard let snapshot = try indexStore.loadIfPresent(),
                  snapshot.rootRevision == authorization.revision,
                  Set(snapshot.roots) == Set(authorizedRoots.map(\.path)) else {
                state = .needsRefresh(folderCount: authorizedRoots.count)
                return
            }
            provider.replaceSnapshot(snapshot)
            state = .ready(
                fileCount: snapshot.entries.count,
                folderCount: authorizedRoots.count,
                generatedAt: snapshot.generatedAt
            )
        } catch is AuthorizedFolderStoreError {
            state = .needsAuthorization
        } catch is AuthorizedFolderBookmarkError {
            state = .needsAuthorization
        } catch is LocalIndexRootPolicyError {
            state = .needsAuthorization
        } catch {
            state = .failed
        }
    }

    public func replaceAuthorizedFolders(
        _ folders: [AuthorizedFolderBookmark]
    ) async throws {
        let acceptedFolders = try normalizedBookmarks(folders)
        invalidateRunningBuild()
        provider.clear()

        let authorization = AuthorizedFolderSet(folders: acceptedFolders)
        do {
            try authorizedFolderStore.save(authorization)
        } catch {
            state = .failed
            throw error
        }
        state = .needsRefresh(folderCount: acceptedFolders.count)
        await rebuild(using: authorization)
    }

    public func rebuild() async {
        do {
            guard let authorization = try authorizedFolderStore.loadSetIfPresent(),
                  !authorization.folders.isEmpty else {
                invalidateRunningBuild()
                provider.clear()
                state = .disabled
                return
            }
            await rebuild(using: authorization)
        } catch is AuthorizedFolderStoreError {
            provider.clear()
            state = .needsAuthorization
        } catch {
            provider.clear()
            state = .failed
        }
    }

    public func cancelRebuild() {
        invalidateRunningBuild()
        let folderCount = (try? authorizedFolderStore.loadSet().folders.count) ?? 0
        state = folderCount == 0
            ? .disabled
            : .needsRefresh(folderCount: folderCount)
    }

    public func clearAll() async throws {
        invalidateRunningBuild()
        provider.clear()
        do {
            // Authorization is removed first. If index deletion later fails, the
            // old cache still cannot be accepted on the next launch.
            try authorizedFolderStore.clear()
            try indexStore.clear()
            state = .disabled
        } catch {
            state = .failed
            throw error
        }
    }

    private func rebuild(using authorization: AuthorizedFolderSet) async {
        let authorizedRoots: [URL]
        do {
            authorizedRoots = try resolveAuthorizedRoots(authorization)
        } catch is AuthorizedFolderBookmarkError {
            provider.clear()
            state = .needsAuthorization
            return
        } catch is LocalIndexRootPolicyError {
            provider.clear()
            state = .needsAuthorization
            return
        } catch {
            provider.clear()
            state = .failed
            return
        }

        invalidateRunningBuild()
        let runID = generation
        state = .indexing(folderCount: authorizedRoots.count)
        let indexer = self.indexer
        let revision = authorization.revision
        let generatedAt = Date()
        let worker = Task.detached(priority: .utility) {
            indexer.buildSnapshot(
                roots: authorizedRoots,
                generatedAt: generatedAt,
                rootRevision: revision,
                isCancelled: { Task<Never, Never>.isCancelled }
            )
        }
        runningTask = worker
        let report = await worker.value

        guard runID == generation else { return }
        runningTask = nil
        guard !report.wasCancelled else {
            state = .needsRefresh(folderCount: authorizedRoots.count)
            return
        }

        let snapshot = LocalIndexSnapshot(
            formatVersion: report.snapshot.formatVersion,
            generatedAt: report.snapshot.generatedAt,
            roots: authorizedRoots.map(\.path),
            entries: report.snapshot.entries,
            rootRevision: revision
        )
        do {
            let currentAuthorization = try authorizedFolderStore.loadSet()
            guard currentAuthorization.revision == revision,
                  runID == generation else {
                return
            }
            try indexStore.save(snapshot)
            guard runID == generation else { return }
            provider.replaceSnapshot(snapshot)
            state = .ready(
                fileCount: snapshot.entries.count,
                folderCount: authorizedRoots.count,
                generatedAt: snapshot.generatedAt
            )
        } catch is AuthorizedFolderStoreError {
            provider.clear()
            state = .needsAuthorization
        } catch {
            provider.clear()
            state = .failed
        }
    }

    private func normalizedBookmarks(
        _ bookmarks: [AuthorizedFolderBookmark]
    ) throws -> [AuthorizedFolderBookmark] {
        let resolvedPairs = try bookmarks.map { bookmark in
            (bookmark, try bookmark.resolve())
        }
        let acceptedRoots = try rootPolicy.validate(resolvedPairs.map(\.1))
        let byPath = Dictionary(
            resolvedPairs.map { ($0.1.path, $0.0) },
            uniquingKeysWith: { first, _ in first }
        )
        return acceptedRoots.compactMap { byPath[$0.path] }
    }

    private func resolveAuthorizedRoots(
        _ authorization: AuthorizedFolderSet
    ) throws -> [URL] {
        try rootPolicy.validate(authorization.folders.map { try $0.resolve() })
    }

    private func invalidateRunningBuild() {
        generation &+= 1
        runningTask?.cancel()
        runningTask = nil
    }
}
