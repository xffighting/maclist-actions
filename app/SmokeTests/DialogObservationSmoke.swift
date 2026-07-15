import CoreGraphics
import Foundation

enum DialogObservationSmoke {
    static func run() {
        let fileDialog = DialogStructureSnapshot(
            role: "AXSheet",
            hasFileContainer: true,
            hasOKButton: true,
            hasCancelButton: true,
            hasFileURLSemantics: true,
            isFocused: true
        )
        precondition(DialogClassifier.isSupportedFileDialog(fileDialog))
        precondition(DialogClassifier.canAutomaticallyAttach(kind: .openFile))
        precondition(!DialogClassifier.canAutomaticallyAttach(kind: .unknown))
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Attach"
        ) == .openFile)
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Open",
            dialogContextText: "Open and Save Panel Service"
        ) == .save)
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Upload",
            dialogContextText: "Choose where to save"
        ) == .save)
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Upload",
            defaultButtonIdentifier: "saveDocument:"
        ) == .save)
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Upload",
            hasSaveFilenameField: true
        ) == .save)
        precondition(DialogClassifier.kind(
            defaultButtonTitle: "Open",
            defaultButtonIdentifier: "ChooseFolder"
        ) == .folder)
        let panelFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        precondition(DialogVisibleStackPolicy.isBoundToHost(
            dialogPID: 99,
            hostPID: 42,
            dialogFrame: panelFrame,
            confidence: 12,
            windows: [
                .init(pid: 99, frame: panelFrame, rank: 0),
                .init(pid: 42, frame: panelFrame.insetBy(dx: -20, dy: -20), rank: 1)
            ]
        ))
        precondition(!DialogClassifier.isSupportedFileDialog(.init(
            role: "AXWindow",
            hasFileContainer: true,
            hasOKButton: false,
            hasCancelButton: false
        )))

        let dialog = ObservedDialog(
            id: "101:sheet-1",
            pid: 101,
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        var machine = DialogObservationStateMachine()
        precondition(machine.handle(.permissionChanged(true)).isEmpty)
        precondition(machine.handle(.frontmostApplicationChanged(101)) == [.observeApplication(101)])
        precondition(machine.handle(.scanCompleted([dialog])) == [.attach(dialog)])
        precondition(machine.handle(.scanCompleted([dialog])).isEmpty)
        let movedDialog = ObservedDialog(
            id: dialog.id,
            pid: dialog.pid,
            frame: dialog.frame.offsetBy(dx: 20, dy: -10)
        )
        precondition(machine.handle(.scanCompleted([movedDialog])) == [.updateAttachment(movedDialog)])
        precondition(machine.handle(.scanCompleted([])) == [.detach])

        var delayedPermission = DialogObservationStateMachine()
        precondition(delayedPermission.handle(.frontmostApplicationChanged(202)).isEmpty)
        precondition(delayedPermission.handle(.permissionChanged(true)) == [.observeApplication(202)])

        let candidates = DialogProcessCandidatePlanner.ordered(
            ownPID: 7,
            hostPID: 42,
            focusedPID: 88,
            attachedPID: nil,
            servicePIDs: [88, 99],
            visibleWindowPIDs: [7, 42, 100, 99]
        )
        precondition(candidates == [88, 99, 42, 100])

        var interaction = DialogInteractionState()
        precondition(interaction.attach(dialogID: "wechat-picker"))
        let firstToken = interaction.token!
        precondition(interaction.isCurrent(firstToken))
        precondition(!interaction.attach(dialogID: "wechat-picker"))
        interaction.detach()
        precondition(!interaction.isCurrent(firstToken))

        let lease = FileDialogInteractionLease(dialogID: "wechat-picker")
        precondition(lease.isValid(for: "wechat-picker"))
        precondition(!lease.consumeIfValid(for: "mail-picker"))
        precondition(lease.consumeIfValid(for: "wechat-picker"))
        precondition(!lease.consumeIfValid(for: "wechat-picker"))
        let invalidatedLease = FileDialogInteractionLease(dialogID: "mail-picker")
        invalidatedLease.invalidate()
        precondition(!invalidatedLease.consumeIfValid(for: "mail-picker"))
        precondition(interaction.attach(dialogID: "mail-picker"))
        precondition(interaction.token != firstToken)
        precondition(DialogAttachmentFocusPolicy.shouldKeepAttached(
            dialogPID: 42,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: false,
            systemFocusedPID: 7,
            systemFocusedTopLevelID: nil,
            ownPID: 7,
            ownPanelIsKey: true,
            focusUnavailableWithinGrace: false,
            hasTopVisibleWindowEvidence: false
        ))
        precondition(!DialogAttachmentFocusPolicy.shouldKeepAttached(
            dialogPID: 42,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: false,
            systemFocusedPID: 55,
            systemFocusedTopLevelID: 901,
            ownPID: 7,
            ownPanelIsKey: false,
            focusUnavailableWithinGrace: false,
            hasTopVisibleWindowEvidence: false
        ))

        let collapsed = AttachedPanelLayout.frame(
            dialogFrame: dialog.frame,
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            expanded: false
        )
        let expanded = AttachedPanelLayout.frame(
            dialogFrame: dialog.frame,
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            expanded: true
        )
        precondition(dialog.frame.contains(collapsed))
        precondition(dialog.frame.contains(expanded))
        precondition(abs(collapsed.maxY - expanded.maxY) < 0.001)

        let secondaryScreen = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let narrowDialog = CGRect(x: -1240, y: 120, width: 260, height: 240)
        let narrowPanel = AttachedPanelLayout.frame(
            dialogFrame: narrowDialog,
            visibleScreenFrame: secondaryScreen,
            expanded: true
        )
        precondition(narrowDialog.contains(narrowPanel))
        precondition(secondaryScreen.insetBy(dx: 8, dy: 8).contains(narrowPanel))
        precondition(!AttachedPanelLayout.canAttach(
            to: CGRect(x: 0, y: 0, width: 180, height: 140)
        ))

        let converted = AXFrameCoordinateConverter.appKitFrame(
            fromAXFrame: CGRect(x: 100, y: 50, width: 900, height: 640),
            primaryScreenHeight: 900
        )
        precondition(converted == CGRect(x: 100, y: 210, width: 900, height: 640))

        print("dialog-observation: ok")
    }
}
