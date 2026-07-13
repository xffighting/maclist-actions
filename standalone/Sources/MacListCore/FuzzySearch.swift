import Foundation

public enum FuzzySearch {
    public static func search(
        _ query: String,
        in files: [IndexedFile],
        limit: Int = 50
    ) -> [SearchMatch] {
        guard limit > 0 else { return [] }
        let tokens = normalize(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        return files.compactMap { file -> SearchMatch? in
            score(file: file, tokens: tokens)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.file.name.count != rhs.file.name.count {
                return lhs.file.name.count < rhs.file.name.count
            }
            let leftName = normalize(lhs.file.name)
            let rightName = normalize(rhs.file.name)
            if leftName != rightName { return leftName < rightName }
            return lhs.file.path < rhs.file.path
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func score(file: IndexedFile, tokens: [String]) -> SearchMatch? {
        let name = normalize(file.name)
        let stem = normalize(URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent)
        let path = normalize(file.path)
        var total = 0
        var matchedOn: MatchField = .filename

        for token in tokens {
            guard let tokenScore = score(token: token, name: name, stem: stem, path: path) else {
                return nil
            }
            total += tokenScore.score
            if tokenScore.field == .path { matchedOn = .path }
        }

        return SearchMatch(file: file, score: total, matchedOn: matchedOn)
    }

    private static func score(
        token: String,
        name: String,
        stem: String,
        path: String
    ) -> (score: Int, field: MatchField)? {
        if name == token { return (1_200, .filename) }
        if stem == token { return (1_100, .filename) }
        if name.hasPrefix(token) { return (950, .filename) }
        if filenameWords(name).contains(where: { $0.hasPrefix(token) }) {
            return (850, .filename)
        }
        if name.contains(token) { return (720, .filename) }
        if let fuzzy = subsequenceScore(needle: token, haystack: name) {
            return (500 + fuzzy, .filename)
        }
        if path.contains(token) { return (420, .path) }
        if let fuzzy = subsequenceScore(needle: token, haystack: path) {
            return (180 + fuzzy, .path)
        }
        return nil
    }

    private static func filenameWords(_ value: String) -> [Substring] {
        value.split { character in
            !character.isLetter && !character.isNumber
        }
    }

    private static func subsequenceScore(needle: String, haystack: String) -> Int? {
        let needleCharacters = Array(needle)
        let haystackCharacters = Array(haystack)
        guard !needleCharacters.isEmpty, needleCharacters.count <= haystackCharacters.count else {
            return nil
        }

        var searchStart = 0
        var firstMatch = 0
        var previousMatch: Int?
        var consecutivePairs = 0
        var totalGaps = 0

        for (needleIndex, character) in needleCharacters.enumerated() {
            guard let match = haystackCharacters[searchStart...].firstIndex(of: character) else {
                return nil
            }
            if needleIndex == 0 { firstMatch = match }
            if let previousMatch {
                let gap = match - previousMatch - 1
                totalGaps += gap
                if gap == 0 { consecutivePairs += 1 }
            }
            previousMatch = match
            searchStart = match + 1
        }

        return max(1, needleCharacters.count * 14 + consecutivePairs * 18 - totalGaps * 3 - firstMatch * 2)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
