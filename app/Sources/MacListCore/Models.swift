import Foundation

public enum FileRecordSource: String, Codable, Sendable {
    case spotlight
    case history
}

public struct FileRecord: Identifiable, Equatable, Sendable {
    public let path: String
    public let displayName: String
    public let lastUsedAt: Date
    public let source: FileRecordSource

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var parentPath: String {
        url.deletingLastPathComponent().path
    }

    public init(
        path: String,
        displayName: String? = nil,
        lastUsedAt: Date,
        source: FileRecordSource
    ) {
        self.path = path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent
        self.lastUsedAt = lastUsedAt
        self.source = source
    }
}
