import Foundation

public enum SpotlightError: Error, LocalizedError, Sendable {
    case unavailable
    case failed(Int32, String)
    case unreadableOutput

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Spotlight 不可用。"
        case let .failed(code, message):
            return "Spotlight 查询失败（\(code)）：\(message)"
        case .unreadableOutput:
            return "Spotlight 返回了无法解析的数据。"
        }
    }
}

public final class SpotlightProvider: @unchecked Sendable {
    public let homeDirectory: URL
    private let executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    public func recentFiles(days: Int = 180, limit: Int = 2_000) throws -> [FileRecord] {
        let safeDays = min(max(days, 1), 730)
        let query = "kMDItemLastUsedDate >= $time.today(-\(safeDays)) && kMDItemContentTypeTree == 'public.content'"
        return try run(query: query, limit: limit)
    }

    public func matchingFiles(_ query: String, limit: Int = 600) throws -> [FileRecord] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return try recentFiles(limit: limit)
        }

        let filenameClauses = tokens.map { token -> String in
            let normalized = token.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            let wildcard = normalized.map(String.init).joined(separator: "*")
            return "kMDItemFSName == '*\(escapeMetadataLiteral(wildcard))*'cd"
        }
        let metadataQuery = "(\(filenameClauses.joined(separator: " && "))) && kMDItemContentTypeTree == 'public.content'"
        return try run(query: metadataQuery, limit: limit)
    }

    private func run(query: String, limit: Int) throws -> [FileRecord] {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw SpotlightError.unavailable
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-onlyin", homeDirectory.path, query]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "未知错误"
            throw SpotlightError.failed(
                process.terminationStatus,
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw SpotlightError.unreadableOutput
        }

        let safeLimit = max(limit, 1)
        var seen = Set<String>()
        var records: [FileRecord] = []
        records.reserveCapacity(min(safeLimit, 1_000))

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let path = String(rawLine)
            guard seen.insert(path).inserted,
                  PrivacyPolicy.shouldInclude(
                    path: path,
                    homeDirectory: homeDirectory,
                    fileManager: fileManager
                  ) else {
                continue
            }

            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let lastUsedAt = (attributes?[.modificationDate] as? Date) ?? .distantPast
            records.append(FileRecord(
                path: path,
                lastUsedAt: lastUsedAt,
                source: .spotlight
            ))
            if records.count >= safeLimit { break }
        }
        return records
    }

    private func escapeMetadataLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
