import Foundation

enum LocalIndexSmoke {
    static func run() throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("MacListLocalIndexSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        let emptyProvider = LocalIndexProvider()
        precondition(emptyProvider.snapshot == .empty)
        precondition(emptyProvider.recentFiles().isEmpty)
        precondition(emptyProvider.matchingFiles("任意客户", limit: 10).isEmpty)

        let root = sandbox.appendingPathComponent("客户资料", isDirectory: true)
        let project = root.appendingPathComponent("远航工业/阿曼阀门升级", isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("最终清单.xlsx")
        let privateDocumentBody = "LOCAL_INDEX_SMOKE_PRIVATE_BODY"
        try Data(privateDocumentBody.utf8).write(to: file)

        let outside = sandbox.appendingPathComponent("Outside", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("must-not-be-indexed.txt")
        try Data("outside".utf8).write(to: outsideFile)
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("linked-outside", isDirectory: true),
            withDestinationURL: outside
        )

        let report = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [root],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let canonicalFilePath = file.resolvingSymlinksInPath().standardizedFileURL.path
        let indexedPaths = report.snapshot.entries.map(\.path)
        precondition(
            indexedPaths == [canonicalFilePath],
            "unexpected local-index paths: \(indexedPaths); inaccessible=\(report.inaccessibleRootCount) skipped=\(report.skippedCount) fileLimit=\(report.reachedLimit) visitLimit=\(report.reachedVisitLimit) cancelled=\(report.wasCancelled)"
        )
        let canonicalOutsidePath = outsideFile.resolvingSymlinksInPath().standardizedFileURL.path
        precondition(!report.snapshot.entries.contains { $0.path == canonicalOutsidePath })

        let matches = LocalIndexProvider(snapshot: report.snapshot)
            .matchingFiles("远航 阿曼升级", limit: 10)
        precondition(matches.map(\.path) == [canonicalFilePath])

        let storeURL = sandbox.appendingPathComponent("store/index.json")
        let store = LocalIndexStore(url: storeURL)
        try store.save(report.snapshot)
        let loadedSnapshot = try store.load()
        precondition(loadedSnapshot == report.snapshot)
        let storedJSON = try String(contentsOf: storeURL, encoding: .utf8)
        precondition(!storedJSON.contains(privateDocumentBody))

        let fileMode = try permissions(at: storeURL)
        let directoryMode = try permissions(at: storeURL.deletingLastPathComponent())
        precondition(fileMode & 0o777 == 0o600)
        precondition(directoryMode & 0o777 == 0o700)

        try store.clear()
        precondition(!fileManager.fileExists(atPath: storeURL.path))

        let canonicalRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let invalidScopeURL = sandbox.appendingPathComponent("invalid-scope/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [canonicalRootPath],
                entries: [LocalIndexEntry(
                    path: canonicalOutsidePath,
                    displayName: outsideFile.lastPathComponent
                )]
            ),
            to: invalidScopeURL
        )
        try expectLoadError(
            LocalIndexStore(url: invalidScopeURL),
            expected: .invalidScope
        )

        let byteLimitURL = sandbox.appendingPathComponent("byte-limit/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [canonicalRootPath],
                entries: [LocalIndexEntry(path: canonicalFilePath, displayName: file.lastPathComponent)]
            ),
            to: byteLimitURL
        )
        try expectLoadError(
            LocalIndexStore(
                url: byteLimitURL,
                limits: LocalIndexStoreLimits(maximumBytes: 64, maximumEntries: 10)
            ),
            expected: .tooLarge
        )

        let entryLimitURL = sandbox.appendingPathComponent("entry-limit/index.json")
        try writeSnapshot(
            LocalIndexSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                roots: [canonicalRootPath],
                entries: [
                    LocalIndexEntry(path: canonicalFilePath, displayName: file.lastPathComponent),
                    LocalIndexEntry(
                        path: root
                            .appendingPathComponent("second.pdf")
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path,
                        displayName: "second.pdf"
                    )
                ]
            ),
            to: entryLimitURL
        )
        try expectLoadError(
            LocalIndexStore(
                url: entryLimitURL,
                limits: LocalIndexStoreLimits(maximumBytes: 1_048_576, maximumEntries: 1)
            ),
            expected: .tooLarge
        )
        print("local-index: ok")
    }

    private static func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private static func writeSnapshot(_ snapshot: LocalIndexSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(snapshot).write(to: url)
    }

    private static func expectLoadError(
        _ store: LocalIndexStore,
        expected: LocalIndexStoreError
    ) throws {
        do {
            _ = try store.load()
            preconditionFailure("unsafe local index unexpectedly loaded")
        } catch let error as LocalIndexStoreError {
            precondition(error == expected)
        }
    }
}
