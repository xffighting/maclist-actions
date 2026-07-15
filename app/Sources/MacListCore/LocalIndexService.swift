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
    case partial(fileCount: Int, folderCount: Int, generatedAt: Date)
    case needsRefresh(folderCount: Int)
    case needsAuthorization
    case failed
}

private struct LocalIndexBuildOutcome: Sendable {
    let report: LocalIndexingReport
    let rootIdentityInvalidated: Bool
}

public actor LocalIndexService {
    public nonisolated let provider: LocalIndexProvider
    public private(set) var state: LocalIndexServiceState = .disabled

    private let authorizedFolderStore: AuthorizedFolderStore
    private let indexStore: LocalIndexStore
    private let indexer: any LocalIndexBuilding
    private let rootPolicy: LocalIndexRootPolicy
    private let rootIdentityValidator: @Sendable ([LocalIndexRootIdentity]) -> Bool
    private var generation: UInt64 = 0
    private var runningTask: Task<LocalIndexBuildOutcome, Never>?

    public init(
        provider: LocalIndexProvider = LocalIndexProvider(),
        authorizedFolderStore: AuthorizedFolderStore = AuthorizedFolderStore(
            url: AuthorizedFolderStore.defaultURL()
        ),
        indexStore: LocalIndexStore = LocalIndexStore(url: LocalIndexStore.defaultURL()),
        indexer: any LocalIndexBuilding = LocalFileIndexer(),
        rootPolicy: LocalIndexRootPolicy = LocalIndexRootPolicy()
    ) {
        self.init(
            provider: provider,
            authorizedFolderStore: authorizedFolderStore,
            indexStore: indexStore,
            indexer: indexer,
            rootPolicy: rootPolicy,
            rootIdentityValidator: { identities in
                identities.allSatisfy { $0.matchesCurrentDirectory() }
            }
        )
    }

    init(
        provider: LocalIndexProvider,
        authorizedFolderStore: AuthorizedFolderStore,
        indexStore: LocalIndexStore,
        indexer: any LocalIndexBuilding,
        rootPolicy: LocalIndexRootPolicy = LocalIndexRootPolicy(),
        rootIdentityValidator: @escaping @Sendable (
            [LocalIndexRootIdentity]
        ) -> Bool
    ) {
        self.provider = provider
        self.authorizedFolderStore = authorizedFolderStore
        self.indexStore = indexStore
        self.indexer = indexer
        self.rootPolicy = rootPolicy
        self.rootIdentityValidator = rootIdentityValidator
    }

    public func bootstrap() async {
        invalidateRunningBuild()
        provider.clear()
        do {
            guard let authorization = try authorizedFolderStore.loadSetIfPresent(),
                  !authorization.folders.isEmpty else {
                state = .disabled
                return
            }
            let authorizedRoots = try resolveAuthorizedRoots(authorization)
            let snapshot: LocalIndexSnapshot?
            do {
                snapshot = try indexStore.loadIfPresent()
            } catch let error as LocalIndexStoreError {
                guard case .unsupportedFormat = error else { throw error }
                do {
                    try indexStore.clear()
                    state = .needsRefresh(folderCount: authorizedRoots.count)
                } catch {
                    state = .failed
                }
                return
            }
            guard let snapshot,
                  snapshot.rootRevision == authorization.revision,
                  Set(snapshot.roots) == Set(authorizedRoots.map(\.path)) else {
                state = .needsRefresh(folderCount: authorizedRoots.count)
                return
            }
            provider.replaceSnapshot(snapshot)
            if snapshot.isComplete {
                state = .ready(
                    fileCount: snapshot.entries.count,
                    folderCount: authorizedRoots.count,
                    generatedAt: snapshot.generatedAt
                )
            } else {
                state = .partial(
                    fileCount: snapshot.entries.count,
                    folderCount: authorizedRoots.count,
                    generatedAt: snapshot.generatedAt
                )
            }
        } catch is AuthorizedFolderStoreError {
            transitionToNeedsAuthorization()
        } catch is AuthorizedFolderBookmarkError {
            transitionToNeedsAuthorization()
        } catch is LocalIndexRootPolicyError {
            transitionToNeedsAuthorization()
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
            try indexStore.clear()
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
            transitionToNeedsAuthorization()
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
        let rootIdentities: [LocalIndexRootIdentity]
        do {
            authorizedRoots = try resolveAuthorizedRoots(authorization)
            rootIdentities = try authorizedRoots.map(LocalIndexRootIdentity.capture)
        } catch is AuthorizedFolderBookmarkError {
            transitionToNeedsAuthorization()
            return
        } catch is LocalIndexRootPolicyError {
            transitionToNeedsAuthorization()
            return
        } catch is LocalIndexRootIdentityError {
            transitionToNeedsAuthorization()
            return
        } catch {
            provider.clear()
            state = .failed
            return
        }

        invalidateRunningBuild()
        provider.clear()
        do {
            // A refresh must not leave an older snapshot searchable while the
            // authorized root can change underneath the detached scan.
            try indexStore.clear()
        } catch {
            state = .failed
            return
        }
        let runID = generation
        state = .indexing(folderCount: authorizedRoots.count)
        let indexer = self.indexer
        let rootIdentityValidator = self.rootIdentityValidator
        let revision = authorization.revision
        let generatedAt = Date()
        let worker = Task.detached(priority: .utility) {
            guard rootIdentityValidator(rootIdentities) else {
                return LocalIndexBuildOutcome(
                    report: LocalIndexingReport(
                        snapshot: LocalIndexSnapshot(
                            generatedAt: generatedAt,
                            roots: authorizedRoots.map(\.path),
                            entries: [],
                            rootRevision: revision,
                            isComplete: false
                        ),
                        skippedCount: 0,
                        inaccessibleRootCount: authorizedRoots.count,
                        reachedLimit: false,
                        wasCancelled: true
                    ),
                    rootIdentityInvalidated: true
                )
            }
            let report = indexer.buildSnapshot(
                roots: authorizedRoots,
                generatedAt: generatedAt,
                rootRevision: revision,
                isCancelled: { Task<Never, Never>.isCancelled }
            )
            guard rootIdentityValidator(rootIdentities) else {
                return LocalIndexBuildOutcome(
                    report: LocalIndexingReport(
                        snapshot: report.snapshot,
                        skippedCount: report.skippedCount,
                        inaccessibleRootCount: report.inaccessibleRootCount,
                        reachedLimit: report.reachedLimit,
                        reachedVisitLimit: report.reachedVisitLimit,
                        accessErrorCount: report.accessErrorCount,
                        wasCancelled: true
                    ),
                    rootIdentityInvalidated: true
                )
            }
            return LocalIndexBuildOutcome(
                report: report,
                rootIdentityInvalidated: false
            )
        }
        runningTask = worker
        let outcome = await worker.value

        guard runID == generation else { return }
        runningTask = nil
        guard !outcome.rootIdentityInvalidated else {
            transitionToNeedsAuthorization()
            return
        }
        let report = outcome.report
        guard !report.wasCancelled else {
            state = .needsRefresh(folderCount: authorizedRoots.count)
            return
        }

        let snapshot = LocalIndexSnapshot(
            formatVersion: LocalIndexSnapshot.currentFormatVersion,
            generatedAt: report.snapshot.generatedAt,
            roots: authorizedRoots.map(\.path),
            entries: report.snapshot.entries,
            rootRevision: revision,
            isComplete: report.snapshot.isComplete
                && !report.reachedLimit
                && !report.reachedVisitLimit
                && report.inaccessibleRootCount == 0
                && report.accessErrorCount == 0
        )
        do {
            let currentAuthorization = try authorizedFolderStore.loadSet()
            guard currentAuthorization == authorization,
                  runID == generation else {
                return
            }
            guard rootIdentityValidator(rootIdentities) else {
                transitionToNeedsAuthorization()
                return
            }
            try indexStore.save(snapshot)
            guard runID == generation else { return }
            guard rootIdentityValidator(rootIdentities) else {
                transitionToNeedsAuthorization()
                return
            }
            provider.replaceSnapshot(snapshot)
            if !snapshot.isComplete {
                state = .partial(
                    fileCount: snapshot.entries.count,
                    folderCount: authorizedRoots.count,
                    generatedAt: snapshot.generatedAt
                )
            } else {
                state = .ready(
                    fileCount: snapshot.entries.count,
                    folderCount: authorizedRoots.count,
                    generatedAt: snapshot.generatedAt
                )
            }
        } catch is AuthorizedFolderStoreError {
            transitionToNeedsAuthorization()
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

    private func transitionToNeedsAuthorization() {
        invalidateRunningBuild()
        provider.clear()
        do {
            try indexStore.clear()
            state = .needsAuthorization
        } catch {
            state = .failed
        }
    }
}
