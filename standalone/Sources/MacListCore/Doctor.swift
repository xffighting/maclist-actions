import Foundation

public enum DoctorStatus: String, Codable, Sendable {
    case pass
    case warning
    case fail
}

public struct DoctorCheck: Codable, Equatable, Sendable {
    public let name: String
    public let status: DoctorStatus
    public let message: String

    public init(name: String, status: DoctorStatus, message: String) {
        self.name = name
        self.status = status
        self.message = message
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let checks: [DoctorCheck]

    public var isHealthy: Bool {
        !checks.contains { $0.status == .fail }
    }

    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }
}

public final class Doctor {
    private let store: IndexStore
    private let fileManager: FileManager

    public init(store: IndexStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func run() -> DoctorReport {
        var checks: [DoctorCheck] = [
            DoctorCheck(
                name: "privacy-model",
                status: .pass,
                message: "The index schema stores only authorized roots, file names, paths, and modification dates."
            )
        ]

        guard fileManager.fileExists(atPath: store.url.path) else {
            checks.append(DoctorCheck(
                name: "index",
                status: .warning,
                message: "No index exists yet. Run the index command with at least one explicit --root."
            ))
            return DoctorReport(checks: checks)
        }

        do {
            let fileMode = try store.permissions(at: store.url) & 0o777
            checks.append(DoctorCheck(
                name: "index-permissions",
                status: fileMode & 0o077 == 0 ? .pass : .fail,
                message: String(format: "Index file mode is %03o (expected no group/other access).", fileMode)
            ))
        } catch {
            checks.append(DoctorCheck(name: "index-permissions", status: .fail, message: error.localizedDescription))
        }

        do {
            let snapshot = try store.load()
            checks.append(DoctorCheck(
                name: "index-format",
                status: .pass,
                message: "Loaded format v\(snapshot.formatVersion) with \(snapshot.files.count) files."
            ))

            let invalidRoots = snapshot.roots.filter { path in
                var isDirectory: ObjCBool = false
                return !fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                    || !isDirectory.boolValue
                    || !fileManager.isReadableFile(atPath: path)
            }
            checks.append(DoctorCheck(
                name: "authorized-roots",
                status: invalidRoots.isEmpty ? .pass : .warning,
                message: invalidRoots.isEmpty
                    ? "All \(snapshot.roots.count) authorized roots are readable."
                    : "\(invalidRoots.count) authorized roots are missing or unreadable; rebuild the index."
            ))

            let outOfScopeCount = snapshot.files.filter { file in
                !snapshot.roots.contains { root in
                    PathScope.contains(path: file.path, root: root)
                }
            }.count
            checks.append(DoctorCheck(
                name: "scope-boundary",
                status: outOfScopeCount == 0 ? .pass : .fail,
                message: outOfScopeCount == 0
                    ? "Every indexed file remains inside an explicitly authorized root."
                    : "Found \(outOfScopeCount) index entries outside the stored root boundaries."
            ))
        } catch {
            checks.append(DoctorCheck(name: "index-format", status: .fail, message: String(describing: error)))
        }

        return DoctorReport(checks: checks)
    }
}
