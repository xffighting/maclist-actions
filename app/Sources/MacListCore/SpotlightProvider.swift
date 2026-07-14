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

public final class SpotlightQueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private weak var process: Process?

    public init() {}

    public func cancel() {
        let runningProcess: Process?
        lock.lock()
        cancelled = true
        runningProcess = process
        lock.unlock()

        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    fileprivate var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func attach(_ process: Process) {
        let shouldCancel: Bool
        lock.lock()
        shouldCancel = cancelled
        if !shouldCancel {
            self.process = process
        }
        lock.unlock()

        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    fileprivate func detach(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }
}

public final class SpotlightProvider: @unchecked Sendable {
    public let homeDirectory: URL
    private let executableURL: URL
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/mdfind"),
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.executableURL = executableURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func recentFiles(
        days: Int = 180,
        limit: Int = 2_000,
        cancellation: SpotlightQueryCancellation? = nil
    ) throws -> [FileRecord] {
        let safeDays = min(max(days, 1), 730)
        let query = "kMDItemLastUsedDate >= $time.today(-\(safeDays)) && kMDItemContentTypeTree == 'public.content'"
        return try run(query: query, limit: limit, cancellation: cancellation)
    }

    public func matchingFiles(
        _ query: String,
        limit: Int = 600,
        cancellation: SpotlightQueryCancellation? = nil
    ) throws -> [FileRecord] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return try recentFiles(limit: limit, cancellation: cancellation)
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
        return try run(
            query: metadataQuery,
            limit: limit,
            cancellation: cancellation
        )
    }

    private func run(
        query: String,
        limit: Int,
        cancellation: SpotlightQueryCancellation?
    ) throws -> [FileRecord] {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw SpotlightError.unavailable
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-0", "-onlyin", homeDirectory.path, query]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        cancellation?.attach(process)
        defer {
            cancellation?.detach(process)
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let safeLimit = max(limit, 1)
        var seen = Set<String>()
        var records: [FileRecord] = []
        records.reserveCapacity(min(safeLimit, 1_000))

        func appendPath(_ data: Data) -> Bool {
            guard !data.isEmpty else { return false }
            guard let path = String(data: data, encoding: .utf8) else { return false }
            guard seen.insert(path).inserted,
                  PrivacyPolicy.shouldIncludeSpotlightPath(
                    path: path,
                    homeDirectory: homeDirectory
                  ) else {
                return false
            }

            records.append(FileRecord(
                path: path,
                lastUsedAt: .distantPast,
                source: .spotlight
            ))
            return records.count >= safeLimit
        }

        let outputHandle = outputPipe.fileHandleForReading
        var buffer = Data()
        var reachedLimit = false
        var wasCancelled = cancellation?.isCancelled ?? false

        if wasCancelled, process.isRunning {
            process.terminate()
        }

        readLoop: while !wasCancelled {
            let chunk: Data
            do {
                chunk = try outputHandle.read(upToCount: 64 * 1_024) ?? Data()
            } catch {
                if cancellation?.isCancelled == true {
                    wasCancelled = true
                    break
                }
                throw error
            }
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let separator = buffer.firstIndex(of: 0) {
                let pathData = buffer.subdata(in: buffer.startIndex..<separator)
                buffer.removeSubrange(buffer.startIndex...separator)
                if appendPath(pathData) {
                    reachedLimit = true
                    break readLoop
                }
            }
            wasCancelled = cancellation?.isCancelled ?? false
        }

        if !reachedLimit, !buffer.isEmpty {
            reachedLimit = appendPath(buffer)
        }
        wasCancelled = wasCancelled || (cancellation?.isCancelled ?? false)
        if (reachedLimit || wasCancelled), process.isRunning {
            process.terminate()
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard reachedLimit || wasCancelled || process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "未知错误"
            throw SpotlightError.failed(
                process.terminationStatus,
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return wasCancelled ? [] : records
    }

    private func escapeMetadataLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
