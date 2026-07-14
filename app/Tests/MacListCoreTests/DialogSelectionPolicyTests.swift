import Foundation
@testable import MacListCore
import XCTest

final class DialogSelectionPolicyTests: XCTestCase {
    private final class PermissionDeniedFileManager: FileManager, @unchecked Sendable {
        override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    func testSelectAndConfirmPlanEndsByConfirmingSelection() {
        XCTAssertEqual(
            DialogSelectionPolicy.plan(for: .selectAndConfirm).last,
            .confirmSelection
        )
    }

    func testSelectOnlyPlanDoesNotConfirmSelection() {
        XCTAssertFalse(
            DialogSelectionPolicy.plan(for: .selectOnly).contains(.confirmSelection)
        )
    }

    func testDirectoryIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclist-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try DialogSelectionPolicy.validateFileURL(directory)) { error in
            guard case DialogSelectionError.directoryNotAllowed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSymlinkAndTargetResolveToSamePhysicalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclist-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("target.pdf")
        let link = directory.appendingPathComponent("alias.pdf")
        try Data("fixture".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let targetFile = try DialogSelectionPolicy.validateFile(target)
        let linkedFile = try DialogSelectionPolicy.validateFile(link)
        XCTAssertEqual(targetFile.url, linkedFile.url)
        XCTAssertEqual(targetFile.identity, linkedFile.identity)
    }

    func testPermissionDeniedPathIsDelegatedToOriginalFileDialog() throws {
        let protectedURL = URL(fileURLWithPath: "/Users/tester/Documents/客户报价单.xlsx")
        let validated = try DialogSelectionPolicy.validateFile(
            protectedURL,
            fileManager: PermissionDeniedFileManager()
        )

        XCTAssertEqual(validated.url, protectedURL.standardizedFileURL)
        XCTAssertNil(validated.identity)
    }

    func testCandidateValidationDoesNotRequireFileSystemAccess() throws {
        let protectedURL = URL(fileURLWithPath: "/Users/tester/Documents/云端占位文件.pdf")
        let validated = try DialogSelectionPolicy.validateCandidate(protectedURL)

        XCTAssertEqual(validated.url, protectedURL.standardizedFileURL)
        XCTAssertNil(validated.identity)
    }
}
