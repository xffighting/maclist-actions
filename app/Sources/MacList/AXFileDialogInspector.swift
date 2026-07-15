import ApplicationServices
import MacListCore

struct AXFileDialogInspection {
    let snapshot: DialogStructureSnapshot
    let confidence: Int
    let kind: DialogKind
    let defaultButton: AXUIElement?
    let authoritativeDefaultButton: AXUIElement?
    let hasSaveFilenameField: Bool
    let fileContainers: [AXUIElement]
}

final class AXFileDialogInspector {
    private let directFileContainerRoles: Set<String> = [
        kAXBrowserRole as String,
        kAXOutlineRole as String,
        kAXListRole as String,
        kAXTableRole as String
    ]

    func inspect(
        _ root: AXUIElement,
        focusedElement: AXUIElement? = nil,
        maxNodes: Int = 700
    ) -> AXFileDialogInspection? {
        guard let role = AXAccess.string(root, kAXRoleAttribute) else { return nil }
        let descendants = AXAccess.descendants(of: root, maxNodes: maxNodes)
        let allElements = [root] + descendants
        let fileContainers = descendants.filter { element in
            guard let role = AXAccess.string(element, kAXRoleAttribute) else { return false }
            return directFileContainerRoles.contains(role)
        }

        let hasFileURLSemantics = allElements.contains { element in
            AXAccess.url(element, kAXURLAttribute) != nil
                || AXAccess.url(element, kAXDocumentAttribute) != nil
                || AXAccess.string(element, kAXFilenameAttribute)?.isEmpty == false
        }
        let hasPathSemantics = allElements.contains { element in
            let identifier = AXAccess.string(element, kAXIdentifierAttribute)?.lowercased() ?? ""
            guard identifier.contains("path")
                    || identifier.contains("location")
                    || identifier.contains("filename") else {
                return false
            }
            let role = AXAccess.string(element, kAXRoleAttribute)
            return role == kAXTextFieldRole as String
                || role == kAXComboBoxRole as String
                || role == kAXStaticTextRole as String
        }

        let authoritativeDefaultButton = AXAccess.element(
            root,
            kAXDefaultButtonAttribute
        )
        let defaultButton = authoritativeDefaultButton
            ?? button(withIdentifier: "OKButton", in: allElements)
        let cancelButton = AXAccess.element(root, kAXCancelButtonAttribute)
            ?? button(withIdentifier: "CancelButton", in: allElements)
        let containerWindow = AXAccess.nearestAncestor(
            from: root,
            matching: [kAXWindowRole as String]
        ) ?? root
        let isFocused = focusedElement.map { focused in
            AXAccess.isSame(focused, root)
                || AXAccess.isAncestor(root, of: focused)
        } ?? (AXAccess.bool(root, kAXFocusedAttribute) ?? false)
        let hasSaveFilenameField = allElements.contains(where: isSaveFilenameField)

        let snapshot = DialogStructureSnapshot(
            role: role,
            hasFileContainer: !fileContainers.isEmpty,
            hasOKButton: defaultButton != nil,
            hasCancelButton: cancelButton != nil,
            hasFileURLSemantics: hasFileURLSemantics,
            hasPathSemantics: hasPathSemantics,
            isModal: AXAccess.bool(root, kAXModalAttribute) ?? false,
            isFocused: isFocused,
            isMinimized: AXAccess.bool(containerWindow, kAXMinimizedAttribute) ?? false,
            isHidden: AXAccess.bool(containerWindow, kAXHiddenAttribute) ?? false,
            defaultButtonTitle: defaultButton.flatMap {
                AXAccess.string($0, kAXTitleAttribute)
            }
        )
        return AXFileDialogInspection(
            snapshot: snapshot,
            confidence: DialogClassifier.confidence(for: snapshot),
            kind: DialogClassifier.kind(
                defaultButtonTitle: snapshot.defaultButtonTitle,
                defaultButtonIdentifier: defaultButton.flatMap {
                    AXAccess.string($0, kAXIdentifierAttribute)
                },
                dialogContextText: [
                    AXAccess.string(root, kAXTitleAttribute),
                    AXAccess.string(root, kAXDescriptionAttribute)
                ].compactMap { $0 }.joined(separator: " "),
                hasSaveFilenameField: hasSaveFilenameField
            ),
            defaultButton: defaultButton,
            authoritativeDefaultButton: authoritativeDefaultButton,
            hasSaveFilenameField: hasSaveFilenameField,
            fileContainers: fileContainers
        )
    }

    private func button(
        withIdentifier identifier: String,
        in elements: [AXUIElement]
    ) -> AXUIElement? {
        elements.first { element in
            AXAccess.string(element, kAXRoleAttribute) == kAXButtonRole as String
                && AXAccess.string(element, kAXIdentifierAttribute) == identifier
        }
    }

    private func isSaveFilenameField(_ element: AXUIElement) -> Bool {
        guard AXAccess.string(element, kAXRoleAttribute) == kAXTextFieldRole as String,
              AXAccess.string(element, kAXSubroleAttribute) != "AXSearchField",
              AXAccess.string(element, kAXSubroleAttribute)
                != kAXSecureTextFieldSubrole as String,
              AXAccess.isSettable(element, kAXValueAttribute) else {
            return false
        }

        let titleElement = AXAccess.element(element, kAXTitleUIElementAttribute)
        let semantics = [
            AXAccess.string(element, kAXIdentifierAttribute),
            AXAccess.string(element, kAXTitleAttribute),
            AXAccess.string(element, kAXDescriptionAttribute),
            AXAccess.string(element, kAXHelpAttribute),
            AXAccess.string(element, "AXPlaceholderValue"),
            titleElement.flatMap { AXAccess.string($0, kAXTitleAttribute) },
            titleElement.flatMap { AXAccess.string($0, kAXValueAttribute) }
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return [
            "filename", "file name", "namefield", "saveas", "save as", "savename",
            "文件名", "檔案名稱", "文件名称", "另存为", "另存為"
        ].contains(where: semantics.contains)
    }
}
