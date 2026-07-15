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
    private var storedInvocationCount = 0

    init(wasCancelled: Bool = false) {
        self.wasCancelled = wasCancelled
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
            inaccessibleRootCount: 0,
            reachedLimit: false,
            wasCancelled: wasCancelled
        )
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
