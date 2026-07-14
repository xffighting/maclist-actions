import Foundation

private final class PermissionDeniedFileManager: FileManager, @unchecked Sendable {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        throw CocoaError(.fileReadNoPermission)
    }
}

@main
enum DialogSelectionPolicySmoke {
    static func main() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclist-dialog-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("报价单.pdf")
        try Data("fixture".utf8).write(to: fileURL)

        let validated = try DialogSelectionPolicy.validateFileURL(fileURL)
        precondition(validated == fileURL.resolvingSymlinksInPath())
        let validatedFile = try DialogSelectionPolicy.validateFile(fileURL)
        precondition(validatedFile.identity != nil)

        let linkURL = temporaryDirectory.appendingPathComponent("报价单-链接.pdf")
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: fileURL
        )
        let linkedFile = try DialogSelectionPolicy.validateFile(linkURL)
        precondition(linkedFile.url == validatedFile.url)
        precondition(linkedFile.identity == validatedFile.identity)

        do {
            _ = try DialogSelectionPolicy.validateFileURL(temporaryDirectory)
            preconditionFailure("directory must be rejected")
        } catch DialogSelectionError.directoryNotAllowed {
            // Expected.
        }

        let missingFile = temporaryDirectory.appendingPathComponent("不存在.pdf")
        let candidate = try DialogSelectionPolicy.validateCandidate(missingFile)
        precondition(candidate.url == missingFile.standardizedFileURL)
        precondition(candidate.identity == nil)
        do {
            _ = try DialogSelectionPolicy.validateFileURL(missingFile)
            preconditionFailure("missing file must be rejected")
        } catch DialogSelectionError.fileMissing {
            // Expected.
        }

        let protectedFile = URL(fileURLWithPath: "/tmp/maclist-protected-home/Documents/受保护报价.pdf")
        let protectedValidation = try DialogSelectionPolicy.validateFile(
            protectedFile,
            fileManager: PermissionDeniedFileManager()
        )
        precondition(protectedValidation.url == protectedFile.standardizedFileURL)
        precondition(protectedValidation.identity == nil)

        let confirmPlan = DialogSelectionPolicy.plan(for: .selectAndConfirm)
        precondition(confirmPlan.last == .confirmSelection)

        let selectOnlyPlan = DialogSelectionPolicy.plan(for: .selectOnly)
        precondition(!selectOnlyPlan.contains(.confirmSelection))

        FuzzySearchSmoke.run()
        try SpotlightProviderSmoke.run()
        DialogObservationSmoke.run()
        print("dialog-selection-policy: ok")
    }
}
