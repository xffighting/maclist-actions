import Foundation

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

        let confirmPlan = DialogSelectionPolicy.plan(for: .selectAndConfirm)
        precondition(confirmPlan.last == .confirmSelection)

        let selectOnlyPlan = DialogSelectionPolicy.plan(for: .selectOnly)
        precondition(!selectOnlyPlan.contains(.confirmSelection))

        FuzzySearchSmoke.run()
        DialogObservationSmoke.run()
        print("dialog-selection-policy: ok")
    }
}
