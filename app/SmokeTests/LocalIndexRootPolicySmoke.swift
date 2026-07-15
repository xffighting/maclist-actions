import Foundation

@main
enum LocalIndexRootPolicySmoke {
    static func main() throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory.appendingPathComponent(
            "MacListLocalIndexRootPolicySmoke-\(UUID().uuidString)",
            isDirectory: true
        )
        let unreadable = sandbox.appendingPathComponent("unreadable", isDirectory: true)
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: unreadable.path
            )
            try? fileManager.removeItem(at: sandbox)
        }
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let allowed = sandbox.appendingPathComponent("allowed/customer-files", isDirectory: true)
        let child = allowed.appendingPathComponent("远航工业/阿曼项目", isDirectory: true)
        let alias = sandbox.appendingPathComponent("customer-files-alias", isDirectory: true)
        let iCloudDrive = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs",
            isDirectory: true
        )
        let cloudProvider = home.appendingPathComponent(
            "Library/CloudStorage/ExampleProvider",
            isDirectory: true
        )
        try fileManager.createDirectory(at: child, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: iCloudDrive, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cloudProvider, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: allowed)

        let policy = LocalIndexRootPolicy(homeDirectory: home, fileManager: fileManager, maxRoots: 8)
        let normalized = try policy.validate([child, alias, allowed, allowed])
        precondition(
            normalized == [allowed.resolvingSymlinksInPath().standardizedFileURL],
            "roots must be canonical, deduplicated, and parent-minimized"
        )

        let allowedCloudRoots = try policy.validate([iCloudDrive, cloudProvider])
        precondition(
            Set(allowedCloudRoots.map(\.path)) == Set([iCloudDrive, cloudProvider].map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            })
        )

        let ordinaryLibrary = home.appendingPathComponent("Library/普通资料", isDirectory: true)
        let mobileDocumentsRoot = home.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        let cloudStorageRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        try fileManager.createDirectory(at: ordinaryLibrary, withIntermediateDirectories: true)

        let forbidden = [
            URL(fileURLWithPath: "/", isDirectory: true),
            home,
            sandbox,
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/System/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            URL(fileURLWithPath: "/private/etc", isDirectory: true),
            URL(fileURLWithPath: "/private/var/db", isDirectory: true),
            home.appendingPathComponent("Library", isDirectory: true),
            ordinaryLibrary,
            mobileDocumentsRoot,
            cloudStorageRoot
        ]
        for root in forbidden {
            try expectPolicyRejection([root], by: policy)
        }

        let file = sandbox.appendingPathComponent("not-a-directory.txt")
        let missing = sandbox.appendingPathComponent("missing", isDirectory: true)
        try Data("file".utf8).write(to: file)
        try fileManager.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o000)],
            ofItemAtPath: unreadable.path
        )
        try expectPolicyRejection([missing], by: policy)
        try expectPolicyRejection([file], by: policy)
        try expectPolicyRejection([unreadable], by: policy)

        let independentRoots = (1...3).map {
            sandbox.appendingPathComponent("independent-\($0)", isDirectory: true)
        }
        for root in independentRoots {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let limitedPolicy = LocalIndexRootPolicy(
            homeDirectory: home,
            fileManager: fileManager,
            maxRoots: 2
        )
        try expectPolicyRejection(independentRoots, by: limitedPolicy)

        print("local-index-root-policy: ok")
    }

    private static func expectPolicyRejection(
        _ roots: [URL],
        by policy: LocalIndexRootPolicy
    ) throws {
        do {
            _ = try policy.validate(roots)
            preconditionFailure(
                "unsafe or invalid root must be rejected: \(roots.map(\.path))"
            )
        } catch is LocalIndexRootPolicyError {
            // Expected: policy failures use one explicit fail-closed error type.
        }
    }
}
