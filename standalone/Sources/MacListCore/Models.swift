import Foundation

public struct IndexedFile: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public let name: String
    public let modifiedAt: Date?

    public var id: String { path }

    public init(path: String, name: String? = nil, modifiedAt: Date? = nil) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.modifiedAt = modifiedAt
    }
}

public struct IndexSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let generatedAt: Date
    public let roots: [String]
    public let files: [IndexedFile]

    public init(
        formatVersion: Int = IndexSnapshot.currentFormatVersion,
        generatedAt: Date,
        roots: [String],
        files: [IndexedFile]
    ) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.roots = roots
        self.files = files
    }
}

public struct IndexingReport: Sendable {
    public let snapshot: IndexSnapshot
    public let skippedCount: Int
    public let warnings: [String]
    public let reachedLimit: Bool

    public init(snapshot: IndexSnapshot, skippedCount: Int, warnings: [String], reachedLimit: Bool) {
        self.snapshot = snapshot
        self.skippedCount = skippedCount
        self.warnings = warnings
        self.reachedLimit = reachedLimit
    }
}

public enum MatchField: String, Codable, Sendable {
    case filename
    case path
}

public struct SearchMatch: Codable, Equatable, Sendable {
    public let file: IndexedFile
    public let score: Int
    public let matchedOn: MatchField

    public init(file: IndexedFile, score: Int, matchedOn: MatchField) {
        self.file = file
        self.score = score
        self.matchedOn = matchedOn
    }
}
