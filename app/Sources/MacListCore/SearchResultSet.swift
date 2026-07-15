import Foundation

public struct SearchResultSet: Equatable, Sendable {
    private var recordsBySource: [FileRecordSource: [String: FileRecord]] = [:]

    public init() {}

    public var allRecords: [FileRecord] {
        var merged: [String: FileRecord] = [:]
        for source in [
            FileRecordSource.spotlight,
            FileRecordSource.history,
            FileRecordSource.localIndex
        ] {
            for (path, record) in recordsBySource[source] ?? [:] {
                merged[path] = record
            }
        }
        return merged.values.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    public mutating func replace(
        _ records: [FileRecord],
        source: FileRecordSource
    ) {
        recordsBySource[source] = Dictionary(
            records
                .filter { $0.source == source }
                .map { ($0.path, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    public mutating func clear(source: FileRecordSource) {
        recordsBySource.removeValue(forKey: source)
    }

    public mutating func clearAll() {
        recordsBySource.removeAll(keepingCapacity: false)
    }
}
