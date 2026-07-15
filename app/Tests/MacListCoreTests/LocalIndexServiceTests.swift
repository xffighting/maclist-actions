import Foundation
import XCTest
@testable import MacListCore

final class LocalIndexServiceTests: XCTestCase {
    func testBootstrapWithoutAuthorizationStaysDisabledAndNeverBuilds() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let staleRoot = sandbox.appendingPathComponent("stale", isDirectory: true)
        let provider = LocalIndexProvider(snapshot: LocalIndexSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: [staleRoot.path],
            entries: [LocalIndexEntry(path: staleRoot.appendingPathComponent("stale.pdf").path)]
        ))
        let builder = ImmediateLocalIndexBuilder()
        let service = makeService(
            sandbox: sandbox,
            provider: provider,
            builder: builder
        )

        await service.bootstrap()

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertEqual(builder.invocationCount, 0)
        guard case .disabled = await service.state else {
            return XCTFail("a fresh install must remain disabled until the user selects folders")
        }
    }

    func testBootstrapLoadsCacheOnlyWhenAuthorizationRevisionMatches() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
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
        let builder = ImmediateLocalIndexBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        await service.bootstrap()

        XCTAssertEqual(provider.snapshot, snapshot)
        XCTAssertEqual(builder.invocationCount, 0)
        guard case .ready(
            fileCount: let fileCount,
            folderCount: let folderCount,
            generatedAt: let readyAt
        ) = await service.state else {
            return XCTFail("matching authorization and cache revisions should be immediately ready")
        }
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(folderCount, 1)
        XCTAssertEqual(readyAt, generatedAt)
    }

    func testBootstrapRejectsCacheWhenAuthorizedFolderWasRecreatedAtSamePath() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let revision = UUID()
        let snapshot = makeSnapshot(
            root: folder,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let stores = makeStores(in: sandbox)
        try stores.authorized.save(AuthorizedFolderSet(
            revision: revision,
            folders: [bookmark]
        ))
        try stores.index.save(snapshot)

        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: folder.appendingPathComponent("冒名文件.pdf").path,
            contents: Data("replacement".utf8)
        ))

        let provider = LocalIndexProvider()
        let builder = ImmediateLocalIndexBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        await service.bootstrap()

        XCTAssertEqual(
            provider.snapshot,
            .empty,
            "a different folder recreated at the same path must not inherit the old cache"
        )
        XCTAssertEqual(builder.invocationCount, 0)
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "a cache tied to a replaced root must be deleted, not merely hidden"
        )
        guard case .needsAuthorization = await service.state else {
            return XCTFail("a stale bookmark must require the user to authorize the folder again")
        }
    }

    func testBootstrapRejectsMismatchedCacheWithoutAutomaticallyScanning() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
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
        let builder = ImmediateLocalIndexBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        await service.bootstrap()

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertEqual(builder.invocationCount, 0)
        guard case .needsRefresh(folderCount: 1) = await service.state else {
            return XCTFail("a cache from another authorization revision must not be trusted")
        }
    }

    func testBootstrapTreatsPreviousSemanticIndexFormatAsNeedsRefresh() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let revision = UUID()
        let stores = makeStores(in: sandbox)
        try stores.authorized.save(AuthorizedFolderSet(
            revision: revision,
            folders: [bookmark]
        ))
        try stores.index.save(LocalIndexSnapshot(
            formatVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            roots: [folder.path],
            entries: [LocalIndexEntry(path: folder.appendingPathComponent("旧结果.pdf").path)],
            rootRevision: revision
        ))
        let provider = LocalIndexProvider()
        let builder = ImmediateLocalIndexBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        await service.bootstrap()

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertEqual(builder.invocationCount, 0)
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "an obsolete semantic cache should be removed before the user rebuilds"
        )
        guard case .needsRefresh(folderCount: 1) = await service.state else {
            return XCTFail("a supported migration path must request refresh instead of failing")
        }
    }

    func testClearAllPreventsOlderBuildFromRepublishingOrRepersisting() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "远航工业")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let provider = LocalIndexProvider()
        let builder = BlockingCancellationIgnoringBuilder()
        let stores = makeStores(in: sandbox)
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )
        let replacement = Task {
            try await service.replaceAuthorizedFolders([bookmark])
        }
        XCTAssertTrue(
            builder.waitUntilBuildStarts(timeout: 2),
            "replaceAuthorizedFolders should start its detached index build"
        )
        defer { builder.finishBuild() }

        try await service.clearAll()
        builder.finishBuild()
        _ = try? await replacement.value

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertNil(try stores.authorized.loadSetIfPresent())
        XCTAssertNil(try stores.index.loadIfPresent())
        guard case .disabled = await service.state else {
            return XCTFail("clearing must win even when an obsolete builder ignores cancellation")
        }
    }

    func testCancelledReportIsNeverCommitted() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "远航工业")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let revision = UUID()
        let stores = makeStores(in: sandbox)
        try stores.authorized.save(AuthorizedFolderSet(
            revision: revision,
            folders: [bookmark]
        ))
        let provider = LocalIndexProvider()
        let builder = ImmediateLocalIndexBuilder(wasCancelled: true)
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )
        await service.bootstrap()

        await service.rebuild()

        XCTAssertEqual(builder.invocationCount, 1)
        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertNil(try stores.index.loadIfPresent())
        guard case .needsRefresh(folderCount: 1) = await service.state else {
            return XCTFail("a cancelled report must leave the authorized folders pending refresh")
        }
    }

    func testReplacingAuthorizationDeletesOldIndexWhenNewBuildIsCancelled() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let oldFolder = try makeAuthorizedFolder(in: sandbox, name: "旧客户资料")
        let newFolder = try makeAuthorizedFolder(in: sandbox, name: "新客户资料")
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
        let builder = ImmediateLocalIndexBuilder(wasCancelled: true)
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        try await service.replaceAuthorizedFolders([newBookmark])

        let replacement = try stores.authorized.loadSet()
        XCTAssertEqual(replacement.folders, [newBookmark])
        XCTAssertNotEqual(replacement.revision, oldRevision)
        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "saving a new authorization must invalidate the old cache even when its build is cancelled"
        )
        guard case .needsRefresh(folderCount: 1) = await service.state else {
            return XCTFail("a cancelled replacement build should remain pending refresh")
        }
    }

    func testRootReplacementDuringBuildCannotPublishOrPersistSnapshot() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
        let movedFolder = sandbox.appendingPathComponent("客户资料-原目录", isDirectory: true)
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let stores = makeStores(in: sandbox)
        let provider = LocalIndexProvider()
        let builder = BlockingCancellationIgnoringBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )
        let replacement = Task {
            try await service.replaceAuthorizedFolders([bookmark])
        }
        XCTAssertTrue(
            builder.waitUntilBuildStarts(timeout: 2),
            "the test must replace the directory only after indexing captures the authorized root"
        )
        defer { builder.finishBuild() }

        try FileManager.default.moveItem(at: folder, to: movedFolder)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: folder.appendingPathComponent("冒名文件.pdf").path,
            contents: Data("replacement".utf8)
        ))
        builder.finishBuild()
        _ = try? await replacement.value

        XCTAssertEqual(
            provider.snapshot,
            .empty,
            "a different directory created at the same path must not inherit the old authorization"
        )
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "a snapshot built after the authorized directory identity changes must not be persisted"
        )
        switch await service.state {
        case .needsRefresh(folderCount: 1), .needsAuthorization:
            break
        default:
            XCTFail("a replaced authorized root must require refresh or renewed authorization")
        }
    }

    func testRootReplacementDuringRefreshClearsPreviouslyLoadedProviderAndCache() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
        let movedFolder = sandbox.appendingPathComponent("客户资料-原目录", isDirectory: true)
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let revision = UUID()
        let previousSnapshot = makeSnapshot(
            root: folder,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let stores = makeStores(in: sandbox)
        try stores.authorized.save(AuthorizedFolderSet(
            revision: revision,
            folders: [bookmark]
        ))
        try stores.index.save(previousSnapshot)
        let provider = LocalIndexProvider(snapshot: previousSnapshot)
        let builder = BlockingCancellationIgnoringBuilder()
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )
        let refresh = Task { await service.rebuild() }
        XCTAssertTrue(builder.waitUntilBuildStarts(timeout: 2))
        defer { builder.finishBuild() }
        XCTAssertEqual(
            provider.snapshot,
            .empty,
            "a refresh must retire the previously published provider before scanning"
        )
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "a refresh must retire the previous cache before the root can change"
        )

        try FileManager.default.moveItem(at: folder, to: movedFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: folder.appendingPathComponent("冒名文件.pdf").path,
            contents: Data("replacement".utf8)
        ))
        builder.finishBuild()
        await refresh.value

        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertNil(
            try stores.index.loadIfPresent(),
            "identity loss during refresh must erase the previously trusted cache"
        )
        guard case .needsAuthorization = await service.state else {
            return XCTFail("identity loss must require renewed authorization")
        }
    }

    func testIdentityIsVerifiedAgainImmediatelyBeforeCommit() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "客户资料")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let stores = makeStores(in: sandbox)
        let provider = LocalIndexProvider()
        let validator = SequencedRootIdentityValidator(failingInvocation: 3)
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: ImmediateLocalIndexBuilder(),
            rootIdentityValidator: { identities in
                validator.validate(identities)
            }
        )

        try await service.replaceAuthorizedFolders([bookmark])

        XCTAssertGreaterThanOrEqual(validator.invocationCount, 3)
        XCTAssertEqual(provider.snapshot, .empty)
        XCTAssertNil(try stores.index.loadIfPresent())
        guard case .needsAuthorization = await service.state else {
            return XCTFail("a root that becomes invalid at the commit boundary must not publish")
        }
    }

    func testReplacingAuthorizedFoldersPersistsRevisionRebuildsAndPublishesReadySnapshot() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let folder = try makeAuthorizedFolder(in: sandbox, name: "远航工业")
        let bookmark = try AuthorizedFolderBookmark.create(for: folder)
        let provider = LocalIndexProvider()
        let builder = ImmediateLocalIndexBuilder()
        let stores = makeStores(in: sandbox)
        let service = LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )

        try await service.replaceAuthorizedFolders([bookmark])

        let authorization = try stores.authorized.loadSet()
        let storedSnapshot = try stores.index.load()
        XCTAssertEqual(authorization.folders, [bookmark])
        XCTAssertEqual(storedSnapshot.rootRevision, authorization.revision)
        XCTAssertEqual(provider.snapshot, storedSnapshot)
        XCTAssertEqual(builder.invocationCount, 1)
        guard case .ready(fileCount: 1, folderCount: 1, generatedAt: _) = await service.state else {
            return XCTFail("a successful replacement build should publish a ready local index")
        }
    }

    func testNonCancelledIncompleteReportsPersistSafeResultsButNeverClaimReady() async throws {
        let scenarios: [(
            name: String,
            reachedLimit: Bool,
            reachedVisitLimit: Bool,
            inaccessibleRootCount: Int,
            snapshotIsComplete: Bool,
            accessErrorCount: Int
        )] = [
            ("file limit", true, false, 0, true, 0),
            ("visit limit", false, true, 0, true, 0),
            ("inaccessible root", false, false, 1, true, 0),
            ("snapshot access error", false, false, 0, false, 1),
            ("counter and snapshot disagree", false, false, 0, true, 1),
        ]

        for scenario in scenarios {
            let sandbox = try makeSandbox()
            defer { try? FileManager.default.removeItem(at: sandbox) }

            let folder = try makeAuthorizedFolder(in: sandbox, name: "远航工业")
            let bookmark = try AuthorizedFolderBookmark.create(for: folder)
            let provider = LocalIndexProvider()
            let builder = ImmediateLocalIndexBuilder(
                reachedLimit: scenario.reachedLimit,
                reachedVisitLimit: scenario.reachedVisitLimit,
                inaccessibleRootCount: scenario.inaccessibleRootCount,
                snapshotIsComplete: scenario.snapshotIsComplete,
                accessErrorCount: scenario.accessErrorCount
            )
            let stores = makeStores(in: sandbox)
            let service = LocalIndexService(
                provider: provider,
                authorizedFolderStore: stores.authorized,
                indexStore: stores.index,
                indexer: builder
            )

            try await service.replaceAuthorizedFolders([bookmark])

            let storedSnapshot = try stores.index.load()
            XCTAssertEqual(
                provider.snapshot,
                storedSnapshot,
                "\(scenario.name) may keep its safe partial results searchable"
            )
            XCTAssertEqual(storedSnapshot.entries.count, 1)
            guard case .partial(
                fileCount: let fileCount,
                folderCount: let folderCount,
                generatedAt: let generatedAt
            ) = await service.state else {
                XCTFail("\(scenario.name) must be visibly partial, never ready")
                continue
            }
            XCTAssertEqual(fileCount, 1)
            XCTAssertEqual(folderCount, 1)
            XCTAssertEqual(generatedAt, storedSnapshot.generatedAt)
        }
    }

    private func makeSandbox() throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacListLocalIndexServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: sandbox,
            withIntermediateDirectories: true
        )
        return sandbox
    }

    private func makeAuthorizedFolder(in sandbox: URL, name: String) throws -> URL {
        let folder = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeStores(
        in sandbox: URL
    ) -> (authorized: AuthorizedFolderStore, index: LocalIndexStore) {
        let privateStore = sandbox.appendingPathComponent("private-store", isDirectory: true)
        return (
            AuthorizedFolderStore(url: privateStore.appendingPathComponent("folders.json")),
            LocalIndexStore(url: privateStore.appendingPathComponent("index.json"))
        )
    }

    private func makeService(
        sandbox: URL,
        provider: LocalIndexProvider,
        builder: any LocalIndexBuilding
    ) -> LocalIndexService {
        let stores = makeStores(in: sandbox)
        return LocalIndexService(
            provider: provider,
            authorizedFolderStore: stores.authorized,
            indexStore: stores.index,
            indexer: builder
        )
    }

    private func makeSnapshot(
        root: URL,
        revision: UUID,
        generatedAt: Date
    ) -> LocalIndexSnapshot {
        LocalIndexSnapshot(
            generatedAt: generatedAt,
            roots: [root.path],
            entries: [
                LocalIndexEntry(path: root.appendingPathComponent("最终清单.xlsx").path)
            ],
            rootRevision: revision
        )
    }
}

private final class ImmediateLocalIndexBuilder: LocalIndexBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private let wasCancelled: Bool
    private let reachedLimit: Bool
    private let reachedVisitLimit: Bool
    private let inaccessibleRootCount: Int
    private let snapshotIsComplete: Bool
    private let accessErrorCount: Int
    private var storedInvocationCount = 0

    init(
        wasCancelled: Bool = false,
        reachedLimit: Bool = false,
        reachedVisitLimit: Bool = false,
        inaccessibleRootCount: Int = 0,
        snapshotIsComplete: Bool = true,
        accessErrorCount: Int = 0
    ) {
        self.wasCancelled = wasCancelled
        self.reachedLimit = reachedLimit
        self.reachedVisitLimit = reachedVisitLimit
        self.inaccessibleRootCount = inaccessibleRootCount
        self.snapshotIsComplete = snapshotIsComplete
        self.accessErrorCount = accessErrorCount
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
                rootRevision: rootRevision,
                isComplete: snapshotIsComplete
            ),
            skippedCount: 0,
            inaccessibleRootCount: inaccessibleRootCount,
            reachedLimit: reachedLimit,
            reachedVisitLimit: reachedVisitLimit,
            accessErrorCount: accessErrorCount,
            wasCancelled: wasCancelled
        )
    }
}

private final class SequencedRootIdentityValidator: @unchecked Sendable {
    private let lock = NSLock()
    private let failingInvocation: Int
    private var storedInvocationCount = 0

    init(failingInvocation: Int) {
        self.failingInvocation = failingInvocation
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInvocationCount
    }

    func validate(_ identities: [LocalIndexRootIdentity]) -> Bool {
        lock.lock()
        storedInvocationCount += 1
        let invocation = storedInvocationCount
        lock.unlock()
        return invocation != failingInvocation
            && identities.allSatisfy { $0.matchesCurrentDirectory() }
    }
}

private final class BlockingCancellationIgnoringBuilder: LocalIndexBuilding, @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func waitUntilBuildStarts(timeout: TimeInterval) -> Bool {
        started.wait(timeout: .now() + timeout) == .success
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
