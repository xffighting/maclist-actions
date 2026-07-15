import Foundation

private final class ServiceSmokeBuilder: LocalIndexBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private let returnsCancelledReport: Bool
    private let reachedLimit: Bool
    private let reachedVisitLimit: Bool
    private let inaccessibleRootCount: Int
    private var storedInvocationCount = 0

    init(
        returnsCancelledReport: Bool = false,
        reachedLimit: Bool = false,
        reachedVisitLimit: Bool = false,
        inaccessibleRootCount: Int = 0
    ) {
        self.returnsCancelledReport = returnsCancelledReport
        self.reachedLimit = reachedLimit
        self.reachedVisitLimit = reachedVisitLimit
        self.inaccessibleRootCount = inaccessibleRootCount
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInvocationCount
    }

    func buildSnapshot(
        roots: [URL],
        generatedAt: Date,
        rootRevision: UUID,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> LocalIndexingReport {
        lock.lock()
        storedInvocationCount += 1
        lock.unlock()
        let canonicalRoots = roots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL
        }
        return LocalIndexingReport(
            snapshot: LocalIndexSnapshot(
                generatedAt: generatedAt,
                roots: canonicalRoots.map(\.path),
                entries: canonicalRoots.first.map {
                    [LocalIndexEntry(path: $0.appendingPathComponent("最终清单.xlsx").path)]
                } ?? [],
                rootRevision: rootRevision
            ),
            skippedCount: 0,
            inaccessibleRootCount: inaccessibleRootCount,
            reachedLimit: reachedLimit,
            reachedVisitLimit: reachedVisitLimit,
            wasCancelled: returnsCancelledReport
        )
    }
}

private final class ServiceSmokeBlockingBuilder: LocalIndexBuilding, @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func waitUntilBuildStarts() -> Bool {
        started.wait(timeout: .now() + 2) == .success
    }

    func finishBuild() {
        release.signal()
    }

    func buildSnapshot(
        roots: [URL],
        generatedAt: Date,
        rootRevision: UUID,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> LocalIndexingReport {
        started.signal()
        release.wait()
        let canonicalRoots = roots.map {
            $0.resolvingSymlinksInPath().standardizedFileURL
        }
        return LocalIndexingReport(
            snapshot: LocalIndexSnapshot(
                generatedAt: generatedAt,
                roots: canonicalRoots.map(\.path),
                entries: canonicalRoots.first.map {
                    [LocalIndexEntry(path: $0.appendingPathComponent("obsolete.pdf").path)]
                } ?? [],
                rootRevision: rootRevision
            ),
            skippedCount: 0,
            inaccessibleRootCount: 0,
            reachedLimit: false,
            wasCancelled: false
        )
    }
}

@main
enum LocalIndexServiceSmoke {
    static func main() async throws {
        try await bootstrapWithoutAuthorizationDoesNotBuild()
        try await matchingRevisionLoadsCache()
        try await mismatchedRevisionDoesNotLoadOrBuild()
        try await cancelledReportDoesNotCommit()
        try await rootReplacementDuringBuildDoesNotCommit()
        try await replacementCancellationDeletesOldIndex()
        try await replacementPersistsRevisionAndPublishes()
        try await incompleteReportsPublishPartialAndPersist()
        try await clearPreventsObsoleteBuildFromReturning()
        print("local-index-service: ok")
    }

    private static func bootstrapWithoutAuthorizationDoesNotBuild() async throws {
        try await withSandbox("disabled") { sandbox in
            let staleRoot = sandbox.appendingPathComponent("stale", isDirectory: true)
            let provider = LocalIndexProvider(snapshot: LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [staleRoot.path],
                entries: [LocalIndexEntry(path: staleRoot.appendingPathComponent("old.pdf").path)]
            ))
            let builder = ServiceSmokeBuilder()
            let stores = makeStores(in: sandbox)
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            await service.bootstrap()

            precondition(provider.snapshot == .empty)
            precondition(builder.invocationCount == 0)
            guard case .disabled = await service.state else {
                preconditionFailure("fresh install must be disabled")
            }
        }
    }

    private static func matchingRevisionLoadsCache() async throws {
        try await withSandbox("matching") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let revision = UUID()
            let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
            let snapshot = makeSnapshot(
                root: folder,
                revision: revision,
                generatedAt: generatedAt
            )
            let stores = makeStores(in: sandbox)
            try stores.authorized.save(AuthorizedFolderSet(
                revision: revision,
                folders: [bookmark]
            ))
            try stores.index.save(snapshot)
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBuilder()
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            await service.bootstrap()

            precondition(provider.snapshot == snapshot)
            precondition(builder.invocationCount == 0)
            guard case .ready(
                fileCount: 1,
                folderCount: 1,
                generatedAt: let readyAt
            ) = await service.state else {
                preconditionFailure("matching cache should be ready")
            }
            precondition(readyAt == generatedAt)
        }
    }

    private static func mismatchedRevisionDoesNotLoadOrBuild() async throws {
        try await withSandbox("mismatch") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let stores = makeStores(in: sandbox)
            try stores.authorized.save(AuthorizedFolderSet(
                revision: UUID(),
                folders: [bookmark]
            ))
            try stores.index.save(makeSnapshot(
                root: folder,
                revision: UUID(),
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBuilder()
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            await service.bootstrap()

            precondition(provider.snapshot == .empty)
            precondition(builder.invocationCount == 0)
            guard case .needsRefresh(folderCount: 1) = await service.state else {
                preconditionFailure("mismatched cache must wait for an explicit rebuild")
            }
        }
    }

    private static func cancelledReportDoesNotCommit() async throws {
        try await withSandbox("cancelled") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let stores = makeStores(in: sandbox)
            try stores.authorized.save(AuthorizedFolderSet(
                revision: UUID(),
                folders: [bookmark]
            ))
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBuilder(returnsCancelledReport: true)
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )
            await service.bootstrap()

            await service.rebuild()

            precondition(builder.invocationCount == 1)
            precondition(provider.snapshot == .empty)
            let persistedIndex = try stores.index.loadIfPresent()
            precondition(persistedIndex == nil)
            guard case .needsRefresh(folderCount: 1) = await service.state else {
                preconditionFailure("cancelled report must not be published")
            }
        }
    }

    private static func replacementCancellationDeletesOldIndex() async throws {
        try await withSandbox("replace-cancelled") { sandbox in
            let oldFolder = try makeFolder(in: sandbox, name: "旧客户资料")
            let newFolder = try makeFolder(in: sandbox, name: "新客户资料")
            let oldBookmark = try AuthorizedFolderBookmark.create(for: oldFolder)
            let newBookmark = try AuthorizedFolderBookmark.create(for: newFolder)
            let oldRevision = UUID()
            let oldSnapshot = makeSnapshot(
                root: oldFolder,
                revision: oldRevision,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let stores = makeStores(in: sandbox)
            try stores.authorized.save(AuthorizedFolderSet(
                revision: oldRevision,
                folders: [oldBookmark]
            ))
            try stores.index.save(oldSnapshot)
            let provider = LocalIndexProvider(snapshot: oldSnapshot)
            let builder = ServiceSmokeBuilder(returnsCancelledReport: true)
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            try await service.replaceAuthorizedFolders([newBookmark])

            let replacement = try stores.authorized.loadSet()
            precondition(replacement.folders == [newBookmark])
            precondition(replacement.revision != oldRevision)
            precondition(provider.snapshot == .empty)
            let persistedIndex = try stores.index.loadIfPresent()
            precondition(
                persistedIndex == nil,
                "new authorization must invalidate the old index before a cancelled build returns"
            )
            guard case .needsRefresh(folderCount: 1) = await service.state else {
                preconditionFailure("cancelled replacement must remain pending refresh")
            }
        }
    }

    private static func rootReplacementDuringBuildDoesNotCommit() async throws {
        try await withSandbox("root-replaced") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let movedFolder = sandbox.appendingPathComponent("客户资料-原目录", isDirectory: true)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let stores = makeStores(in: sandbox)
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBlockingBuilder()
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )
            let replacement = Task {
                try await service.replaceAuthorizedFolders([bookmark])
            }
            precondition(
                builder.waitUntilBuildStarts(),
                "root replacement must happen after the build captures its authorization"
            )
            defer { builder.finishBuild() }

            try FileManager.default.moveItem(at: folder, to: movedFolder)
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            precondition(FileManager.default.createFile(
                atPath: folder.appendingPathComponent("冒名文件.pdf").path,
                contents: Data("replacement".utf8)
            ))
            builder.finishBuild()
            _ = try? await replacement.value

            precondition(
                provider.snapshot == .empty,
                "a directory recreated at the same path must not inherit authorization"
            )
            let persistedIndex = try stores.index.loadIfPresent()
            precondition(
                persistedIndex == nil,
                "a build whose root identity changed must not be persisted"
            )
            switch await service.state {
            case .needsRefresh(folderCount: 1), .needsAuthorization:
                break
            default:
                preconditionFailure("replaced root must require refresh or authorization")
            }
        }
    }

    private static func replacementPersistsRevisionAndPublishes() async throws {
        try await withSandbox("replace") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let stores = makeStores(in: sandbox)
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBuilder()
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            try await service.replaceAuthorizedFolders([bookmark])

            let authorization = try stores.authorized.loadSet()
            let snapshot = try stores.index.load()
            precondition(authorization.folders == [bookmark])
            precondition(snapshot.rootRevision == authorization.revision)
            precondition(provider.snapshot == snapshot)
            precondition(builder.invocationCount == 1)
            guard case .ready(fileCount: 1, folderCount: 1, generatedAt: _) = await service.state else {
                preconditionFailure("replacement should become ready")
            }
        }
    }

    private static func incompleteReportsPublishPartialAndPersist() async throws {
        let scenarios: [(
            name: String,
            reachedLimit: Bool,
            reachedVisitLimit: Bool,
            inaccessibleRootCount: Int
        )] = [
            ("file-limit", true, false, 0),
            ("visit-limit", false, true, 0),
            ("inaccessible-root", false, false, 1),
        ]

        for scenario in scenarios {
            try await withSandbox("partial-\(scenario.name)") { sandbox in
                let folder = try makeFolder(in: sandbox)
                let bookmark = try AuthorizedFolderBookmark.create(for: folder)
                let stores = makeStores(in: sandbox)
                let provider = LocalIndexProvider()
                let builder = ServiceSmokeBuilder(
                    reachedLimit: scenario.reachedLimit,
                    reachedVisitLimit: scenario.reachedVisitLimit,
                    inaccessibleRootCount: scenario.inaccessibleRootCount
                )
                let service = LocalIndexService(
                    provider: provider,
                    authorizedFolderStore: stores.authorized,
                    indexStore: stores.index,
                    indexer: builder
                )

                try await service.replaceAuthorizedFolders([bookmark])

                let storedSnapshot = try stores.index.load()
                precondition(provider.snapshot == storedSnapshot)
                precondition(storedSnapshot.entries.count == 1)
                guard case .partial(
                    fileCount: 1,
                    folderCount: 1,
                    generatedAt: let generatedAt
                ) = await service.state else {
                    preconditionFailure("\(scenario.name) must be partial, never ready")
                }
                precondition(generatedAt == storedSnapshot.generatedAt)
            }
        }
    }

    private static func clearPreventsObsoleteBuildFromReturning() async throws {
        try await withSandbox("clear") { sandbox in
            let folder = try makeFolder(in: sandbox)
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let stores = makeStores(in: sandbox)
            let provider = LocalIndexProvider()
            let builder = ServiceSmokeBlockingBuilder()
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )
            let replacement = Task {
                try await service.replaceAuthorizedFolders([bookmark])
            }
            precondition(builder.waitUntilBuildStarts())
            defer { builder.finishBuild() }

            try await service.clearAll()
            builder.finishBuild()
            _ = try? await replacement.value

            precondition(provider.snapshot == .empty)
            let persistedAuthorization = try stores.authorized.loadSetIfPresent()
            let persistedIndex = try stores.index.loadIfPresent()
            precondition(persistedAuthorization == nil)
            precondition(persistedIndex == nil)
            guard case .disabled = await service.state else {
                preconditionFailure("clear must win over an obsolete build")
            }
        }
    }

    private static func withSandbox(
        _ name: String,
        operation: (URL) async throws -> Void
    ) async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacListLocalIndexServiceSmoke-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: sandbox,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try await operation(sandbox)
    }

    private static func makeFolder(
        in sandbox: URL,
        name: String = "客户资料"
    ) throws -> URL {
        let folder = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func makeStores(
        in sandbox: URL
    ) -> (authorized: AuthorizedFolderStore, index: LocalIndexStore) {
        let privateStore = sandbox.appendingPathComponent("private-store", isDirectory: true)
        return (
            AuthorizedFolderStore(url: privateStore.appendingPathComponent("folders.json")),
            LocalIndexStore(url: privateStore.appendingPathComponent("index.json"))
        )
    }

    private static func makeSnapshot(
        root: URL,
        revision: UUID,
        generatedAt: Date
    ) -> LocalIndexSnapshot {
        LocalIndexSnapshot(
            generatedAt: generatedAt,
            roots: [root.path],
            entries: [LocalIndexEntry(path: root.appendingPathComponent("最终清单.xlsx").path)],
            rootRevision: revision
        )
    }
}
