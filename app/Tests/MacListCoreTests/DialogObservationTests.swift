import CoreGraphics
@testable import MacListCore
import XCTest

final class DialogObservationTests: XCTestCase {
    func testSupportedDialogRequiresFileContainerAndBothActions() {
        XCTAssertTrue(DialogClassifier.isSupportedFileDialog(.init(
            role: "AXSheet",
            hasFileContainer: true,
            hasOKButton: true,
            hasCancelButton: true,
            hasFileURLSemantics: true,
            isFocused: true
        )))
        XCTAssertFalse(DialogClassifier.isSupportedFileDialog(.init(
            role: "AXWindow",
            hasFileContainer: true,
            hasOKButton: false,
            hasCancelButton: false
        )))
    }

    func testClassifierRejectsGenericModalAndRecognizesDialogKind() {
        XCTAssertFalse(DialogClassifier.isSupportedFileDialog(.init(
            role: "AXWindow",
            hasFileContainer: true,
            hasOKButton: true,
            hasCancelButton: true,
            isModal: true,
            isFocused: true
        )))
        XCTAssertEqual(DialogClassifier.kind(defaultButtonTitle: "打开"), .openFile)
        XCTAssertEqual(DialogClassifier.kind(defaultButtonTitle: "Save"), .save)
        XCTAssertEqual(DialogClassifier.kind(defaultButtonTitle: "选择"), .unknown)
        XCTAssertEqual(
            DialogClassifier.kind(
                defaultButtonTitle: "Attach"
            ),
            .openFile
        )
        XCTAssertEqual(
            DialogClassifier.kind(
                defaultButtonTitle: "Choisir",
                hasSaveFilenameField: true
            ),
            .save
        )
        XCTAssertEqual(
            DialogClassifier.kind(
                defaultButtonTitle: "Open",
                dialogContextText: "Open and Save Panel Service"
            ),
            .openFile
        )
        XCTAssertEqual(
            DialogClassifier.kind(
                defaultButtonTitle: "Upload",
                dialogContextText: "Choose where to save"
            ),
            .openFile
        )
        XCTAssertTrue(DialogClassifier.canAutomaticallyAttach(kind: .openFile))
        XCTAssertFalse(DialogClassifier.canAutomaticallyAttach(kind: .unknown))
        XCTAssertFalse(DialogClassifier.canAutomaticallyAttach(kind: .save))
    }

    func testDialogLifecycleAttachesUpdatesAndDetaches() {
        var state = DialogObservationStateMachine()
        let dialog = ObservedDialog(
            id: "42:sheet",
            pid: 42,
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )

        XCTAssertEqual(state.handle(.permissionChanged(true)), [])
        XCTAssertEqual(
            state.handle(.frontmostApplicationChanged(42)),
            [.observeApplication(42)]
        )
        XCTAssertEqual(state.handle(.scanCompleted([dialog])), [.attach(dialog)])

        let moved = ObservedDialog(
            id: dialog.id,
            pid: dialog.pid,
            frame: dialog.frame.offsetBy(dx: 20, dy: 0)
        )
        XCTAssertEqual(
            state.handle(.scanCompleted([moved])),
            [.updateAttachment(moved)]
        )
        XCTAssertEqual(state.handle(.scanCompleted([])), [.detach])
    }

    func testDialogSelectionKeepsCurrentThenPrefersFocusedConfidence() {
        var state = DialogObservationStateMachine()
        _ = state.handle(.permissionChanged(true))
        _ = state.handle(.frontmostApplicationChanged(42))
        let first = ObservedDialog(
            id: "first",
            pid: 42,
            frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            confidence: 10,
            isFocused: true
        )
        let second = ObservedDialog(
            id: "second",
            pid: 42,
            frame: CGRect(x: 30, y: 30, width: 600, height: 400),
            confidence: 20,
            isFocused: false
        )
        XCTAssertEqual(state.handle(.scanCompleted([second, first])), [.attach(first)])
        XCTAssertTrue(state.handle(.scanCompleted([first, second])).isEmpty)

        let hiddenFirst = ObservedDialog(
            id: "first",
            pid: 42,
            frame: first.frame,
            confidence: 10,
            isFocused: false,
            isVisible: false
        )
        XCTAssertEqual(
            state.handle(.scanCompleted([hiddenFirst, second])),
            [.detach, .attach(second)]
        )
    }

    func testPermissionGrantedAfterFrontmostAppStartsObserver() {
        var state = DialogObservationStateMachine()
        XCTAssertEqual(state.handle(.frontmostApplicationChanged(99)), [])
        XCTAssertEqual(
            state.handle(.permissionChanged(true)),
            [.observeApplication(99)]
        )
    }

    func testDialogProcessCandidatesIncludeOutOfProcessPanelWithoutDuplicates() {
        XCTAssertEqual(
            DialogProcessCandidatePlanner.ordered(
                ownPID: 7,
                hostPID: 42,
                focusedPID: 88,
                attachedPID: nil,
                servicePIDs: [88, 99],
                visibleWindowPIDs: [7, 42, 100, 99]
            ),
            [88, 99, 42, 100]
        )
    }

    func testAttachedDialogPIDStaysFirstDuringOutOfProcessScan() {
        XCTAssertEqual(
            DialogProcessCandidatePlanner.ordered(
                ownPID: 7,
                hostPID: 42,
                focusedPID: 42,
                attachedPID: 99,
                servicePIDs: [99],
                visibleWindowPIDs: [42, 99]
            ),
            [99, 42]
        )
    }

    func testInteractionTokenExpiresWhenDialogClosesOrChanges() {
        var state = DialogInteractionState()
        XCTAssertTrue(state.attach(dialogID: "wechat-picker"))
        let first = try! XCTUnwrap(state.token)
        XCTAssertTrue(state.isCurrent(first))

        XCTAssertFalse(state.attach(dialogID: "wechat-picker"))
        XCTAssertTrue(state.isCurrent(first))

        state.detach()
        XCTAssertFalse(state.isCurrent(first))

        XCTAssertTrue(state.attach(dialogID: "mail-picker"))
        let second = try! XCTUnwrap(state.token)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(state.isCurrent(second))
    }

    func testOwnNonactivatingPanelFocusDoesNotDropAttachment() {
        XCTAssertTrue(DialogAttachmentFocusPolicy.shouldKeepAttached(
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
        XCTAssertFalse(DialogAttachmentFocusPolicy.shouldKeepAttached(
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
        XCTAssertTrue(DialogAttachmentFocusPolicy.shouldKeepAttached(
            dialogPID: 42,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: true,
            systemFocusedPID: 42,
            systemFocusedTopLevelID: 900,
            ownPID: 7,
            ownPanelIsKey: false,
            focusUnavailableWithinGrace: false,
            hasTopVisibleWindowEvidence: false
        ))
        XCTAssertFalse(DialogAttachmentFocusPolicy.shouldKeepAttached(
            dialogPID: 42,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: false,
            systemFocusedPID: nil,
            systemFocusedTopLevelID: nil,
            ownPID: 7,
            ownPanelIsKey: false,
            focusUnavailableWithinGrace: false,
            hasTopVisibleWindowEvidence: false
        ))
        XCTAssertFalse(DialogAttachmentFocusPolicy.shouldKeepAttached(
            dialogPID: 42,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: false,
            systemFocusedPID: 7,
            systemFocusedTopLevelID: nil,
            ownPID: 7,
            ownPanelIsKey: false,
            focusUnavailableWithinGrace: true,
            hasTopVisibleWindowEvidence: false
        ))
    }

    func testBackgroundServiceCannotAttachFromStaleLocalFocus() {
        XCTAssertFalse(DialogAttachmentFocusPolicy.shouldAttach(
            dialogPID: 99,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: true,
            isOnlyCandidateInProcess: true,
            systemFocusedPID: 42,
            systemFocusedTopLevelID: 901,
            hasTopVisibleWindowEvidence: false
        ))
        XCTAssertTrue(DialogAttachmentFocusPolicy.shouldAttach(
            dialogPID: 99,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: true,
            isOnlyCandidateInProcess: true,
            systemFocusedPID: 42,
            systemFocusedTopLevelID: 900,
            hasTopVisibleWindowEvidence: false
        ))
        XCTAssertTrue(DialogAttachmentFocusPolicy.shouldAttach(
            dialogPID: 99,
            hostPID: 42,
            dialogTopLevelID: 900,
            dialogIsLocallyFocused: false,
            isOnlyCandidateInProcess: true,
            systemFocusedPID: 42,
            systemFocusedTopLevelID: 901,
            hasTopVisibleWindowEvidence: true
        ))
    }

    func testVisibleWindowGeometryRequiresStrongOverlap() {
        XCTAssertTrue(DialogWindowGeometry.isLikelySameWindow(
            CGRect(x: 100, y: 100, width: 800, height: 600),
            CGRect(x: 92, y: 92, width: 816, height: 624)
        ))
        XCTAssertFalse(DialogWindowGeometry.isLikelySameWindow(
            CGRect(x: 100, y: 100, width: 800, height: 600),
            CGRect(x: 1_200, y: 100, width: 800, height: 600)
        ))
    }

    func testVisibleWindowStackBindsPanelOnlyToWindowImmediatelyBelow() {
        let panel = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(DialogVisibleStackPolicy.isBoundToHost(
            dialogPID: 99,
            hostPID: 42,
            dialogFrame: panel,
            confidence: 12,
            windows: [
                .init(pid: 99, frame: panel, rank: 0),
                .init(pid: 42, frame: panel.insetBy(dx: -30, dy: -30), rank: 1)
            ]
        ))
        XCTAssertFalse(DialogVisibleStackPolicy.isBoundToHost(
            dialogPID: 99,
            hostPID: 42,
            dialogFrame: panel,
            confidence: 12,
            windows: [
                .init(pid: 42, frame: panel.offsetBy(dx: 20, dy: 20), rank: 0),
                .init(pid: 99, frame: panel, rank: 1),
                .init(pid: 7, frame: panel.insetBy(dx: -30, dy: -30), rank: 2)
            ]
        ))
    }

    func testAttachedLayoutStaysInsideDialogAndSharesTopEdge() {
        let dialog = CGRect(x: 100, y: 100, width: 900, height: 640)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let collapsed = AttachedPanelLayout.frame(
            dialogFrame: dialog,
            visibleScreenFrame: screen,
            expanded: false
        )
        let expanded = AttachedPanelLayout.frame(
            dialogFrame: dialog,
            visibleScreenFrame: screen,
            expanded: true
        )

        XCTAssertTrue(dialog.contains(collapsed))
        XCTAssertTrue(dialog.contains(expanded))
        XCTAssertEqual(collapsed.maxY, expanded.maxY, accuracy: 0.001)
    }

    func testAttachedLayoutHandlesNarrowAndNegativeCoordinateDialogs() {
        let screen = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let dialog = CGRect(x: -1240, y: 120, width: 260, height: 240)
        let expanded = AttachedPanelLayout.frame(
            dialogFrame: dialog,
            visibleScreenFrame: screen,
            expanded: true
        )
        XCTAssertTrue(dialog.contains(expanded))
        XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(expanded))
        XCTAssertLessThanOrEqual(expanded.width, 228)
    }

    func testAttachedLayoutUsesVisibleIntersectionForPartlyOffscreenDialog() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let dialog = CGRect(x: -120, y: 100, width: 700, height: 500)
        let frame = AttachedPanelLayout.frame(
            dialogFrame: dialog,
            visibleScreenFrame: screen,
            expanded: true
        )
        XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(frame))
        XCTAssertTrue(dialog.intersects(frame))
    }

    func testAttachmentRejectsPathologicallySmallWindows() {
        XCTAssertFalse(AttachedPanelLayout.canAttach(
            to: CGRect(x: 0, y: 0, width: 180, height: 140)
        ))
        XCTAssertTrue(AttachedPanelLayout.canAttach(
            to: CGRect(x: 0, y: 0, width: 600, height: 400)
        ))
    }
}
