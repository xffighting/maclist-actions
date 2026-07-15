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

        let allowedTitles = [
            "Open", "打开", "開啟",
            "Choose File", "Select File", "Attach", "Attach File", "Upload",
            "选择文件", "選擇檔案", "选择附件", "選擇附件", "上传", "上傳"
        ]
        for title in allowedTitles {
            let context = DialogConfirmationContext(
                kind: .openFile,
                defaultButtonTitle: title,
                exactSelectionVerified: true,
                isCurrentSession: true
            )
            precondition(DialogSelectionPolicy.confirmationDecision(for: context) == .allow)
            precondition(
                DialogSelectionPolicy.plan(
                    for: .selectAndConfirm,
                    confirmationContext: context
                ).last == .confirmSelection
            )
        }

        let rejectedTitles: [String?] = [
            nil, "", "OK", "Continue", "Choose", "Select",
            "Save", "Replace", "Send", "发送", "Open and Send", "Upload and Send"
        ]
        for title in rejectedTitles {
            let context = DialogConfirmationContext(
                kind: .openFile,
                defaultButtonTitle: title,
                exactSelectionVerified: true,
                isCurrentSession: true
            )
            precondition(
                DialogSelectionPolicy.confirmationDecision(for: context)
                    == .deny(.unsafeDefaultAction)
            )
        }

        for kind in [DialogKind.save, .folder, .unknown] {
            let context = DialogConfirmationContext(
                kind: kind,
                defaultButtonTitle: "Open",
                exactSelectionVerified: true,
                isCurrentSession: true
            )
            precondition(
                DialogSelectionPolicy.confirmationDecision(for: context)
                    == .deny(.unsupportedDialogKind(kind))
            )
        }

        let unverifiedContext = DialogConfirmationContext(
            kind: .openFile,
            defaultButtonTitle: "Open",
            exactSelectionVerified: false,
            isCurrentSession: true
        )
        precondition(
            DialogSelectionPolicy.confirmationDecision(for: unverifiedContext)
                == .deny(.exactSelectionNotVerified)
        )

        let staleContext = DialogConfirmationContext(
            kind: .openFile,
            defaultButtonTitle: "Open",
            exactSelectionVerified: true,
            isCurrentSession: false
        )
        precondition(
            DialogSelectionPolicy.confirmationDecision(for: staleContext)
                == .deny(.staleDialogSession)
        )

        precondition(
            !DialogSelectionPolicy.plan(for: .selectAndConfirm).contains(.confirmSelection)
        )
        precondition(
            !DialogSelectionPolicy.plan(
                for: .selectOnly,
                confirmationContext: DialogConfirmationContext(
                    kind: .openFile,
                    defaultButtonTitle: "Open",
                    exactSelectionVerified: true,
                    isCurrentSession: true
                )
            ).contains(.confirmSelection)
        )

        let safeConfirmation = DialogConfirmationSafetyContext(
            mode: .selectAndConfirm,
            sessionKind: .openFile,
            freshKind: .openFile,
            hasSaveFilenameField: false,
            defaultButtonTitle: "Open",
            targetPath: "/tmp/客户/报价单.pdf",
            selectedPaths: ["/tmp/客户/报价单.pdf"],
            hasUnresolvedSelection: false,
            isCurrentSession: true,
            isOperationActive: true,
            ownerIsRunning: true,
            originalWindowIsVisible: true,
            hasCancelButton: true,
            windowPIDMatchesOwner: true,
            buttonPIDMatchesOwner: true,
            windowRoleIsSupported: true,
            buttonRoleIsButton: true,
            buttonIsAuthoritativeDefault: true,
            buttonIsDescendantOfOriginalWindow: true,
            topLevelMatchesOriginalWindow: true,
            originalWindowIsFocused: true,
            buttonIsEnabled: true,
            buttonSupportsPress: true
        )
        precondition(
            DialogConfirmationSafetyPolicy.decision(for: safeConfirmation) == .allow
        )

        let multipleSelection = DialogConfirmationSafetyContext(
            mode: .selectAndConfirm,
            sessionKind: .openFile,
            freshKind: .openFile,
            hasSaveFilenameField: false,
            defaultButtonTitle: "Open",
            targetPath: "/tmp/客户/报价单.pdf",
            selectedPaths: [
                "/tmp/客户/报价单.pdf",
                "/tmp/客户/另一份.pdf"
            ],
            hasUnresolvedSelection: false,
            isCurrentSession: true,
            isOperationActive: true,
            ownerIsRunning: true,
            originalWindowIsVisible: true,
            hasCancelButton: true,
            windowPIDMatchesOwner: true,
            buttonPIDMatchesOwner: true,
            windowRoleIsSupported: true,
            buttonRoleIsButton: true,
            buttonIsAuthoritativeDefault: true,
            buttonIsDescendantOfOriginalWindow: true,
            topLevelMatchesOriginalWindow: true,
            originalWindowIsFocused: true,
            buttonIsEnabled: true,
            buttonSupportsPress: true
        )
        precondition(
            DialogConfirmationSafetyPolicy.decision(for: multipleSelection)
                == .deny(.exactSelectionNotVerified)
        )

        FuzzySearchSmoke.run()
        try SpotlightProviderSmoke.run()
        DialogObservationSmoke.run()
        try AuthorizedFolderBookmarkSmoke.run()
        try LocalIndexSmoke.run()
        SearchResultSetSmoke.run()
        SearchEpochSmoke.run()
        print("dialog-selection-policy: ok")
    }
}
