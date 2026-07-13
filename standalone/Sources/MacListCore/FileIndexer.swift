import Foundation

public struct FileIndexingOptions: Equatable, Sendable {
    public var includeHidden: Bool
    public var maximumFiles: Int

    public init(includeHidden: Bool = false, maximumFiles: Int = 250_000) {
        self.includeHidden = includeHidden
        self.maximumFiles = max(1, maximumFiles)
    }
}

public final class FileIndexer {
    private let fileManager: FileManager
    private let options: FileIndexingOptions

    public init(
        fileManager: FileManager = .default,
        options: FileIndexingOptions = FileIndexingOptions()
    ) {
        self.fileManager = fileManager
        self.options = options
    }

    public func buildSnapshot(
        roots: [AuthorizedRoot],
        generatedAt: Date = Date()
    ) -> IndexingReport {
        var filesByPath: [String: IndexedFile] = [:]
        var skippedCount = 0
        var warnings: [String] = []
        var reachedLimit = false

        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        rootLoop: for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root.url,
                includingPropertiesForKeys: resourceKeys,
                options: enumerationOptions,
                errorHandler: { url, error in
                    warnings.append("Could not inspect \(url.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                warnings.append("Could not enumerate authorized root: \(root.path)")
                continue
            }

            while let candidate = enumerator.nextObject() as? URL {
                if filesByPath.count >= options.maximumFiles {
                    reachedLimit = true
                    break rootLoop
                }

                do {
                    let values = try candidate.resourceValues(forKeys: Set(resourceKeys))
                    if values.isSymbolicLink == true {
                        skippedCount += 1
                        continue
                    }
                    if values.isDirectory == true {
                        continue
                    }
                    guard values.isRegularFile == true, root.contains(candidate) else {
                        skippedCount += 1
                        continue
                    }

                    let standardizedPath = PathScope.canonicalPath(candidate.path)
                    filesByPath[standardizedPath] = IndexedFile(
                        path: standardizedPath,
                        name: candidate.lastPathComponent,
                        modifiedAt: values.contentModificationDate
                    )
                } catch {
                    skippedCount += 1
                    warnings.append("Could not read metadata for \(candidate.path): \(error.localizedDescription)")
                }
            }
        }

        if reachedLimit {
            warnings.append("Stopped after reaching the configured \(options.maximumFiles)-file limit.")
        }

        let files = filesByPath.values.sorted { lhs, rhs in
            let leftName = lhs.name.lowercased()
            let rightName = rhs.name.lowercased()
            if leftName == rightName { return lhs.path < rhs.path }
            return leftName < rightName
        }
        let snapshot = IndexSnapshot(
            generatedAt: generatedAt,
            roots: roots.map(\.path),
            files: files
        )
        return IndexingReport(
            snapshot: snapshot,
            skippedCount: skippedCount,
            warnings: warnings,
            reachedLimit: reachedLimit
        )
    }
}
