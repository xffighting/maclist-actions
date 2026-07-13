import Foundation
import Darwin

public enum RootAuthorizationError: Error, CustomStringConvertible, Equatable {
    case relativePath(String)
    case missing(String)
    case notDirectory(String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .relativePath(let path):
            return "Authorized roots must be absolute paths: \(path)"
        case .missing(let path):
            return "Authorized root does not exist: \(path)"
        case .notDirectory(let path):
            return "Authorized root is not a directory: \(path)"
        case .unreadable(let path):
            return "Authorized root is not readable: \(path)"
        }
    }
}

public struct AuthorizedRoot: Hashable, Sendable {
    public let path: String

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(path: String, fileManager: FileManager = .default) throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard (expandedPath as NSString).isAbsolutePath else {
            throw RootAuthorizationError.relativePath(path)
        }

        let canonicalURL = URL(
            fileURLWithPath: PathScope.canonicalPath(expandedPath),
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory) else {
            throw RootAuthorizationError.missing(canonicalURL.path)
        }
        guard isDirectory.boolValue else {
            throw RootAuthorizationError.notDirectory(canonicalURL.path)
        }
        guard fileManager.isReadableFile(atPath: canonicalURL.path) else {
            throw RootAuthorizationError.unreadable(canonicalURL.path)
        }

        self.path = canonicalURL.path
    }

    public static func authorize(
        paths: [String],
        fileManager: FileManager = .default
    ) throws -> [AuthorizedRoot] {
        let roots = try paths.map { try AuthorizedRoot(path: $0, fileManager: fileManager) }
        return Array(Set(roots)).sorted { $0.path < $1.path }
    }

    public func contains(_ fileURL: URL) -> Bool {
        let candidate = PathScope.canonicalPath(fileURL.path)
        return PathScope.contains(path: candidate, root: path)
    }
}

enum PathScope {
    static func canonicalPath(_ path: String) -> String {
        let resolvedPath = path.withCString { pointer in
            guard let resolved = realpath(pointer, nil) else {
                return URL(fileURLWithPath: path).standardizedFileURL.path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return normalizeDarwinAlias(resolvedPath)
    }

    private static func normalizeDarwinAlias(_ path: String) -> String {
        for alias in ["/var", "/tmp", "/etc"] {
            if path == alias || path.hasPrefix(alias + "/") {
                return "/private" + path
            }
        }
        return path
    }

    static func contains(path: String, root: String) -> Bool {
        let normalizedPath = canonicalPath(path)
        let normalizedRoot = canonicalPath(root)
        if normalizedRoot == "/" { return normalizedPath.hasPrefix("/") }
        return normalizedPath.hasPrefix(normalizedRoot + "/")
    }
}
