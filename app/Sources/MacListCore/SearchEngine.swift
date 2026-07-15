import Foundation

public enum SearchEngine {
    public static func search(
        _ query: String,
        in records: [FileRecord],
        limit: Int = 100,
        now: Date = Date()
    ) -> [FileRecord] {
        let normalizedQuery = normalize(query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLimit = max(limit, 1)

        guard !normalizedQuery.isEmpty else {
            return Array(records.sorted { lhs, rhs in
                if lhs.lastUsedAt == rhs.lastUsedAt {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }.prefix(safeLimit))
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return records.compactMap { record -> (record: FileRecord, score: Double)? in
            guard let score = score(record, tokens: tokens, now: now) else { return nil }
            return (record, score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.record.lastUsedAt == rhs.record.lastUsedAt {
                    return lhs.record.path.localizedStandardCompare(rhs.record.path)
                        == .orderedAscending
                }
                return lhs.record.lastUsedAt > rhs.record.lastUsedAt
            }
            return lhs.score > rhs.score
        }
        .prefix(safeLimit)
        .map(\.record)
    }

    private static func score(
        _ record: FileRecord,
        tokens: [String],
        now: Date
    ) -> Double? {
        let name = normalize(record.displayName)
        let path = normalize(record.path)
        var score = 0.0

        for token in tokens {
            if name == token {
                score += 180
            } else if name.hasPrefix(token) {
                score += 135
            } else if name.contains(token) {
                score += 95
            } else if path.contains(token) {
                score += 48
            } else if isSubsequence(token, of: name) {
                score += 30
            } else if isSubsequence(token, of: path) {
                score += 18
            } else {
                return nil
            }
        }

        let ageDays = max(0, now.timeIntervalSince(record.lastUsedAt) / 86_400)
        score += max(0, 24 - min(ageDays, 24))
        if record.source == .history { score += 8 }
        return score
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let candidate = iterator.next() {
                if candidate == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }
}
