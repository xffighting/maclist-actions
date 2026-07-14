import AppKit
import ApplicationServices
import MacListCore

struct DialogFocusSnapshot: Equatable {
    let pid: pid_t
    let topLevelID: CFHashCode
    let frame: CGRect?
}

struct DialogVisibleWindowSnapshot: Equatable {
    let pid: pid_t
    let frame: CGRect
    let rank: Int
}

final class DialogProcessDiscovery {
    func candidatePIDs(
        ownPID: pid_t,
        hostPID: pid_t?,
        attachedPID: pid_t?,
        focusedPID: pid_t? = nil,
        visibleWindows: [DialogVisibleWindowSnapshot]
    ) -> [pid_t] {
        let candidates = DialogProcessCandidatePlanner.ordered(
            ownPID: Int32(ownPID),
            hostPID: hostPID.map { Int32($0) },
            focusedPID: (focusedPID ?? focusSnapshot()?.pid).map { Int32($0) },
            attachedPID: attachedPID.map { Int32($0) },
            servicePIDs: openSavePanelServicePIDs().map { Int32($0) },
            visibleWindowPIDs: visibleWindows.map { Int32($0.pid) }
        )
        return candidates.map { pid_t($0) }
    }

    func focusSnapshot() -> DialogFocusSnapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApplication = AXAccess.element(
            systemWide,
            kAXFocusedApplicationAttribute
        ) else {
            return nil
        }
        let focused = AXAccess.element(
            focusedApplication,
            kAXFocusedUIElementAttribute
        ) ?? AXAccess.element(
            focusedApplication,
            kAXFocusedWindowAttribute
        ) ?? focusedApplication
        let topLevel = AXAccess.nearestAncestor(
            from: focused,
            matching: [kAXSheetRole as String, kAXWindowRole as String]
        ) ?? AXAccess.topLevelElement(for: focused) ?? focused
        guard let pid = pid(of: topLevel) ?? pid(of: focused) else { return nil }
        return DialogFocusSnapshot(
            pid: pid,
            topLevelID: CFHash(topLevel),
            frame: AXAccess.rawFrame(topLevel)
        )
    }

    func isOpenSavePanelService(_ application: NSRunningApplication) -> Bool {
        let identifiers = [
            application.bundleIdentifier,
            application.executableURL?.lastPathComponent,
            application.localizedName
        ]
        .compactMap { $0?.lowercased() }

        return identifiers.contains { value in
            value.contains("openandsavepanel")
                || value.contains("open-save-panel")
                || value.contains("open and save panel")
                || value.contains("opensavepanel")
        }
    }

    private func openSavePanelServicePIDs() -> [pid_t] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            isOpenSavePanelService(application) ? application.processIdentifier : nil
        }
    }

    func visibleWindowSnapshots(
        excluding ownPID: pid_t
    ) -> [DialogVisibleWindowSnapshot] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var result: [DialogVisibleWindowSnapshot] = []
        var rank = 0
        for window in windows {
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let modalPanelLevel = Int(CGWindowLevelForKey(.modalPanelWindow))
            guard layer >= 0, layer <= modalPanelLevel, alpha > 0.01,
                  let owner = window[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }

            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 240, frame.height >= 120 else { continue }

            let pid = pid_t(owner.int32Value)
            guard pid != ownPID else { continue }
            result.append(DialogVisibleWindowSnapshot(pid: pid, frame: frame, rank: rank))
            rank += 1
            if result.count == 8 { break }
        }
        return result
    }

    private func pid(of element: AXUIElement) -> pid_t? {
        var value: pid_t = 0
        guard AXUIElementGetPid(element, &value) == .success, value > 0 else {
            return nil
        }
        return value
    }
}
