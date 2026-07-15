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
        precondition(
            report.snapshot.isComplete,
            "policy-based skips must not make an otherwise successful index partial"
        )
        precondition(
            report.accessErrorCount == 0,
            "policy-based skips must remain distinct from filesystem access errors"
        )

        let partialRoot = sandbox.appendingPathComponent(
            "PartialCustomerFiles",
            isDirectory: true
        )
        let blockedChild = partialRoot.appendingPathComponent(
            "BlockedProject",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: blockedChild,
            withIntermediateDirectories: true
        )
        let safePartialFile = partialRoot.appendingPathComponent("visible.pdf")
        try Data("safe metadata fixture".utf8).write(to: safePartialFile)
        try Data("blocked metadata fixture".utf8).write(
            to: blockedChild.appendingPathComponent("hidden-from-enumerator.pdf")
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o000)],
            ofItemAtPath: blockedChild.path
        )
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: blockedChild.path
            )
        }

        let partialReport = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false)
        ).buildSnapshot(
            roots: [partialRoot],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let canonicalSafePartialPath = safePartialFile
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        precondition(
            partialReport.snapshot.entries.contains { $0.path == canonicalSafePartialPath },
            "safe results collected before or alongside an enumeration error must be retained"
        )
        precondition(
            !partialReport.snapshot.isComplete,
            "a child-directory enumeration error must make the snapshot partial"
        )
        precondition(partialReport.accessErrorCount > 0)

        let metadataRoot = sandbox.appendingPathComponent(
            "MetadataAccessError",
            isDirectory: true
        )
        try fileManager.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
        let metadataSafeFile = metadataRoot.appendingPathComponent("safe.txt")
        let metadataDeniedFile = metadataRoot.appendingPathComponent("metadata-denied.txt")
        try Data("safe".utf8).write(to: metadataSafeFile)
        try Data("denied".utf8).write(to: metadataDeniedFile)

        let metadataErrorReport = LocalFileIndexer(
            options: LocalFileIndexingOptions(maximumFiles: 100, includeHidden: false),
            resourceValueLoader: { candidate, keys in
                if candidate.lastPathComponent == metadataDeniedFile.lastPathComponent,
                   keys.contains(.isRegularFileKey) {
                    throw SyntheticLocalIndexMetadataError.denied
                }
                return try candidate.resourceValues(forKeys: keys)
            }
        ).buildSnapshot(
            roots: [metadataRoot],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        precondition(
            metadataErrorReport.snapshot.entries.map(\.path) == [
                metadataSafeFile.resolvingSymlinksInPath().standardizedFileURL.path
            ]
        )
        precondition(metadataErrorReport.skippedCount == 0)
        precondition(metadataErrorReport.accessErrorCount == 1)
        precondition(!metadataErrorReport.snapshot.isComplete)

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
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
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

private enum SyntheticLocalIndexMetadataError: Error {
    case denied
}
