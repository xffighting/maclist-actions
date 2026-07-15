import Foundation
import Darwin

public enum LocalIndexRootIdentityError: Error, Equatable {
    case unavailable(String)
    case notDirectory(String)
}

public struct LocalIndexRootIdentity: Equatable, Sendable {
    public let path: String
    public let deviceID: UInt64
    public let fileID: UInt64

    public static func capture(_ url: URL) throws -> LocalIndexRootIdentity {
        let canonical = url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var information = stat()
        let result = canonical.path.withCString { path in
            Darwin.lstat(path, &information)
        }
        guard result == 0 else {
            throw LocalIndexRootIdentityError.unavailable(canonical.path)
        }
        guard information.st_mode & S_IFMT == S_IFDIR else {
            throw LocalIndexRootIdentityError.notDirectory(canonical.path)
        }
        return LocalIndexRootIdentity(
            path: canonical.path,
            deviceID: UInt64(information.st_dev),
            fileID: UInt64(information.st_ino)
        )
    }

    public func matchesCurrentDirectory() -> Bool {
        guard let current = try? Self.capture(URL(fileURLWithPath: path, isDirectory: true)) else {
            return false
        }
        return current == self
    }
}
