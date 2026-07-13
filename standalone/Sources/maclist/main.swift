import Darwin
import Foundation
import MacListCore

private enum CLIError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        }
    }
}

private struct IndexOutput: Encodable {
    let indexedFiles: Int
    let authorizedRoots: [String]
    let skippedEntries: Int
    let reachedLimit: Bool
    let warningCount: Int
    let store: String
}

private struct SearchOutput: Encodable {
    let query: String
    let matchCount: Int
    let matches: [SearchMatch]
}

@main
private enum MacListCLI {
    static func main() {
        do {
            let status = try run(Array(CommandLine.arguments.dropFirst()))
            exit(Int32(status))
        } catch {
            writeError("maclist: \(error)\n\n\(shortUsage)")
            exit(2)
        }
    }

    private static func run(_ arguments: [String]) throws -> Int {
        guard let command = arguments.first else {
            print(fullUsage)
            return 0
        }

        let tail = Array(arguments.dropFirst())
        switch command {
        case "index": return try runIndex(tail)
        case "search": return try runSearch(tail)
        case "doctor": return try runDoctor(tail)
        case "help", "--help", "-h":
            print(fullUsage)
            return 0
        default:
            throw CLIError.usage("Unknown command: \(command)")
        }
    }

    private static func runIndex(_ arguments: [String]) throws -> Int {
        var roots: [String] = []
        var storePath: String?
        var maximumFiles = 250_000
        var json = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--root":
                roots.append(try value(after: &index, in: arguments, option: "--root"))
            case "--store":
                storePath = try value(after: &index, in: arguments, option: "--store")
            case "--max-files":
                let raw = try value(after: &index, in: arguments, option: "--max-files")
                guard let parsed = Int(raw), parsed > 0 else {
                    throw CLIError.usage("--max-files must be a positive integer")
                }
                maximumFiles = parsed
            case "--json": json = true
            case "--help", "-h":
                print(indexUsage)
                return 0
            default:
                throw CLIError.usage("Unknown index option: \(arguments[index])")
            }
            index += 1
        }

        guard !roots.isEmpty else {
            throw CLIError.usage("index requires at least one explicit --root /absolute/path")
        }

        let authorizedRoots = try AuthorizedRoot.authorize(paths: roots)
        let report = FileIndexer(options: FileIndexingOptions(maximumFiles: maximumFiles))
            .buildSnapshot(roots: authorizedRoots)
        let store = makeStore(path: storePath)
        try store.save(report.snapshot)

        let output = IndexOutput(
            indexedFiles: report.snapshot.files.count,
            authorizedRoots: report.snapshot.roots,
            skippedEntries: report.skippedCount,
            reachedLimit: report.reachedLimit,
            warningCount: report.warnings.count,
            store: store.url.path
        )
        if json {
            try printJSON(output)
        } else {
            print("Indexed \(output.indexedFiles) files from \(output.authorizedRoots.count) explicitly authorized root(s).")
            print("Store: \(output.store)")
            if output.skippedEntries > 0 || output.warningCount > 0 {
                print("Skipped: \(output.skippedEntries); warnings: \(output.warningCount)")
            }
            if output.reachedLimit {
                print("The maximum file limit was reached; narrow the roots or raise --max-files.")
            }
        }
        return 0
    }

    private static func runSearch(_ arguments: [String]) throws -> Int {
        var queryParts: [String] = []
        var storePath: String?
        var limit = 50
        var json = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--store":
                storePath = try value(after: &index, in: arguments, option: "--store")
            case "--limit":
                let raw = try value(after: &index, in: arguments, option: "--limit")
                guard let parsed = Int(raw), parsed > 0 else {
                    throw CLIError.usage("--limit must be a positive integer")
                }
                limit = parsed
            case "--json": json = true
            case "--help", "-h":
                print(searchUsage)
                return 0
            default:
                if arguments[index].hasPrefix("--") {
                    throw CLIError.usage("Unknown search option: \(arguments[index])")
                }
                queryParts.append(arguments[index])
            }
            index += 1
        }

        let query = queryParts.joined(separator: " ")
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.usage("search requires a filename or path query")
        }

        let snapshot = try makeStore(path: storePath).load()
        let matches = FuzzySearch.search(query, in: snapshot.files, limit: limit)
        if json {
            try printJSON(SearchOutput(query: query, matchCount: matches.count, matches: matches))
        } else {
            for match in matches {
                print("\(match.score)\t\(match.file.path)")
            }
        }
        return 0
    }

    private static func runDoctor(_ arguments: [String]) throws -> Int {
        var storePath: String?
        var json = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--store":
                storePath = try value(after: &index, in: arguments, option: "--store")
            case "--json": json = true
            case "--help", "-h":
                print(doctorUsage)
                return 0
            default:
                throw CLIError.usage("Unknown doctor option: \(arguments[index])")
            }
            index += 1
        }

        let report = Doctor(store: makeStore(path: storePath)).run()
        if json {
            try printJSON(report)
        } else {
            for check in report.checks {
                print("[\(check.status.rawValue.uppercased())] \(check.name): \(check.message)")
            }
        }
        return report.isHealthy ? 0 : 1
    }

    private static func makeStore(path: String?) -> IndexStore {
        guard let path else {
            return IndexStore(
                url: IndexStore.defaultURL(),
                directoryPolicy: .privateAppDirectory
            )
        }
        let expanded = (path as NSString).expandingTildeInPath
        return IndexStore(
            url: URL(fileURLWithPath: expanded),
            directoryPolicy: .preserveExisting
        )
    }

    private static func value(after index: inout Int, in arguments: [String], option: String) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw CLIError.usage("Missing value after \(option)")
        }
        return arguments[index]
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard let output = String(data: data, encoding: .utf8) else { return }
        print(output)
    }

    private static func writeError(_ value: String) {
        FileHandle.standardError.write(Data(value.utf8))
    }

    private static let shortUsage = "Usage: maclist <index|search|doctor> [options]"

    private static let fullUsage = """
    MacList Standalone — local filename and path search for explicitly authorized folders.

    \(shortUsage)

      maclist index  --root /absolute/folder [--root ...] [--store FILE] [--max-files N] [--json]
      maclist search QUERY [--store FILE] [--limit N] [--json]
      maclist doctor [--store FILE] [--json]

    No root is scanned implicitly. No document contents are read or stored.
    """

    private static let indexUsage = "Usage: maclist index --root /absolute/folder [--root ...] [--store FILE] [--max-files N] [--json]"
    private static let searchUsage = "Usage: maclist search QUERY [--store FILE] [--limit N] [--json]"
    private static let doctorUsage = "Usage: maclist doctor [--store FILE] [--json]"
}
