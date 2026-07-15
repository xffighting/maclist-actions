import Foundation
import XCTest
@testable import MacListCore

final class LocalIndexRootPolicyTests: XCTestCase {
    func testCanonicalizesDeduplicatesAndRemovesRootsCoveredByAParent() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let parent = sandbox.appendingPathComponent("allowed/customer-files", isDirectory: true)
        let child = parent.appendingPathComponent("远航工业/阿曼项目", isDirectory: true)
        let alias = sandbox.appendingPathComponent("customer-files-alias", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)

        let roots = try LocalIndexRootPolicy(
            homeDirectory: home,
            fileManager: .default,
            maxRoots: 8
        ).validate([child, alias, parent, parent])

        XCTAssertEqual(
            roots,
            [parent.resolvingSymlinksInPath().standardizedFileURL]
        )
    }

    func testRejectsFilesystemHomeAndSensitiveSystemRootsBeforeIndexing() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let regularLibraryFolder = home.appendingPathComponent("Library/普通资料", isDirectory: true)
        let mobileDocumentsRoot = home.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        let cloudStorageRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: regularLibraryFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mobileDocumentsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudStorageRoot, withIntermediateDirectories: true)

        let policy = LocalIndexRootPolicy(homeDirectory: home, fileManager: .default, maxRoots: 8)
        let rejectedRoots = [
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
            regularLibraryFolder,
            mobileDocumentsRoot,
            cloudStorageRoot
        ]

        for root in rejectedRoots {
            assertPolicyRejects([root], policy: policy)
        }
    }

    func testAllowsExistingTemporaryAndApprovedCloudStorageRoots() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let temporaryFolder = sandbox.appendingPathComponent("allowed-temp-root", isDirectory: true)
        let iCloudDrive = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs",
            isDirectory: true
        )
        let cloudProvider = home.appendingPathComponent(
            "Library/CloudStorage/ExampleProvider",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iCloudDrive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudProvider, withIntermediateDirectories: true)

        let roots = try LocalIndexRootPolicy(
            homeDirectory: home,
            fileManager: .default,
            maxRoots: 8
        ).validate([temporaryFolder, iCloudDrive, cloudProvider])

        XCTAssertEqual(
            Set(roots.map(\.path)),
            Set([temporaryFolder, iCloudDrive, cloudProvider].map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            })
        )
    }

    func testRejectsMissingFilesAndUnreadableDirectories() throws {
        let sandbox = try makeSandbox()
        let unreadable = sandbox.appendingPathComponent("unreadable", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: unreadable.path
            )
            try? FileManager.default.removeItem(at: sandbox)
        }

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let file = sandbox.appendingPathComponent("not-a-directory.txt")
        let missing = sandbox.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: file)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o000)],
            ofItemAtPath: unreadable.path
        )

        let policy = LocalIndexRootPolicy(homeDirectory: home, fileManager: .default, maxRoots: 8)
        assertPolicyRejects([missing], policy: policy)
        assertPolicyRejects([file], policy: policy)
        assertPolicyRejects([unreadable], policy: policy)
    }

    func testRejectsMoreThanMaximumIndependentRootsAfterDeduplication() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let home = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let roots = (1...3).map {
            sandbox.appendingPathComponent("allowed-\($0)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        for root in roots {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let policy = LocalIndexRootPolicy(homeDirectory: home, fileManager: .default, maxRoots: 2)
        assertPolicyRejects(roots, policy: policy)
    }

    private func assertPolicyRejects(
        _ roots: [URL],
        policy: LocalIndexRootPolicy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try policy.validate(roots), file: file, line: line) { error in
            XCTAssertTrue(
                error is LocalIndexRootPolicyError,
                "unexpected error type: \(error)",
                file: file,
                line: line
            )
        }
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacListLocalIndexRootPolicyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
