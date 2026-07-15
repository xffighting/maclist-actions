import Foundation

public enum LocalIndexRootPolicyError: Error, Equatable {
    case emptySelection
    case tooManyRoots(maximum: Int)
    case invalidRoot(String)
    case unreadableRoot(String)
    case rootTooBroad(String)
}

public struct LocalIndexRootPolicy: @unchecked Sendable {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let maxRoots: Int

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        maxRoots: Int = 16
    ) {
        self.homeDirectory = Self.canonicalURL(homeDirectory)
        self.fileManager = fileManager
        self.maxRoots = max(1, maxRoots)
    }

    public func validate(_ roots: [URL]) throws -> [URL] {
        guard !roots.isEmpty else {
            throw LocalIndexRootPolicyError.emptySelection
        }

        var seen = Set<String>()
        var normalized: [URL] = []
        for root in roots {
            let canonical = Self.canonicalURL(root)
            guard canonical.isFileURL,
                  (canonical.path as NSString).isAbsolutePath else {
                throw LocalIndexRootPolicyError.invalidRoot(root.path)
            }
            guard !isForbidden(canonical) else {
                throw LocalIndexRootPolicyError.rootTooBroad(canonical.path)
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: canonical.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw LocalIndexRootPolicyError.invalidRoot(canonical.path)
            }
            guard fileManager.isReadableFile(atPath: canonical.path),
                  Self.hasReadablePermissionBit(canonical, fileManager: fileManager) else {
                throw LocalIndexRootPolicyError.unreadableRoot(canonical.path)
            }
            if seen.insert(canonical.path).inserted {
                normalized.append(canonical)
            }
        }

        let minimized = normalized
            .sorted { lhs, rhs in
                let lhsDepth = lhs.pathComponents.count
                let rhsDepth = rhs.pathComponents.count
                if lhsDepth == rhsDepth { return lhs.path < rhs.path }
                return lhsDepth < rhsDepth
            }
            .reduce(into: [URL]()) { accepted, candidate in
                guard !accepted.contains(where: {
                    Self.contains(candidate.path, inside: $0.path)
                }) else { return }
                accepted.append(candidate)
            }

        guard minimized.count <= maxRoots else {
            throw LocalIndexRootPolicyError.tooManyRoots(maximum: maxRoots)
        }
        return minimized
    }

    private func isForbidden(_ candidate: URL) -> Bool {
        let path = candidate.path
        let homePath = homeDirectory.path

        if path == "/" { return true }
        if Self.contains(homePath, inside: path) { return true }

        let iCloudDrive = Self.canonicalURL(
            homeDirectory.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs",
                isDirectory: true
            )
        ).path
        if Self.contains(path, inside: iCloudDrive) { return false }

        let cloudStorage = Self.canonicalURL(
            homeDirectory.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        ).path
        if path != cloudStorage, Self.contains(path, inside: cloudStorage) {
            return false
        }

        let userLibrary = Self.canonicalURL(
            homeDirectory.appendingPathComponent("Library", isDirectory: true)
        ).path
        if Self.contains(path, inside: userLibrary) { return true }

        let temporaryRoot = Self.canonicalURL(fileManager.temporaryDirectory).path
        if Self.contains(path, inside: temporaryRoot) { return false }

        for protectedRoot in [
            "/System", "/Library", "/private", "/etc", "/var", "/tmp"
        ] {
            if Self.contains(path, inside: protectedRoot) { return true }
        }

        return false
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private static func contains(_ path: String, inside root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func hasReadablePermissionBit(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let permissions = try? fileManager
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.intValue & 0o444 != 0
    }
}
