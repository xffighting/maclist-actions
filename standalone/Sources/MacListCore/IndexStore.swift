import Foundation

public enum StoreDirectoryPolicy: Equatable, Sendable {
    case privateAppDirectory
    case preserveExisting
}

public enum IndexStoreError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case unsupportedFormat(Int)

    public var description: String {
        switch self {
        case .notFound(let path):
            return "No index found at \(path). Run `maclist index --root /absolute/path` first."
        case .unsupportedFormat(let version):
            return "Unsupported index format version \(version). Rebuild the index."
        }
    }
}

public final class IndexStore {
    public let url: URL
    public let directoryPolicy: StoreDirectoryPolicy
    private let fileManager: FileManager

    public init(
        url: URL,
        directoryPolicy: StoreDirectoryPolicy = .preserveExisting,
        fileManager: FileManager = .default
    ) {
        self.url = url.standardizedFileURL
        self.directoryPolicy = directoryPolicy
        self.fileManager = fileManager
    }

    public static func defaultURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/MacListStandalone", isDirectory: true)
            .appendingPathComponent("index.json", isDirectory: false)
    }

    public func save(_ snapshot: IndexSnapshot) throws {
        try prepareDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load() throws -> IndexSnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            throw IndexStoreError.notFound(url.path)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(IndexSnapshot.self, from: data)
        guard snapshot.formatVersion == IndexSnapshot.currentFormatVersion else {
            throw IndexStoreError.unsupportedFormat(snapshot.formatVersion)
        }
        return snapshot
    }

    public func permissions(at target: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: target.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let existed = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)

        if existed, !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists)
        }
        if !existed {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if directoryPolicy == .privateAppDirectory || !existed {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }
}
