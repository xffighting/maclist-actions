import AppKit
import ApplicationServices
import MacListCore

enum FileDialogMonitorStatus: Equatable {
    case permissionRequired
    case watching(String)
    case waitingForApplication
}

private struct AXNotificationRegistration {
    let element: AXUIElement
    let notification: CFString
}

final class FileDialogMonitor {
    var onAttach: ((FileDialogSession, ObservedDialog) -> Void)?
    var onUpdate: ((FileDialogSession, ObservedDialog) -> Void)?
    var onDetach: (() -> Void)?
    var onStatusChange: ((FileDialogMonitorStatus) -> Void)?
    var isAttachedPanelKey: (() -> Bool)?

    private let detector: FileDialogDetector
    private let processDiscovery: DialogProcessDiscovery
    private let scanQueue = DispatchQueue(
        label: "app.maclist.dialog-scan",
        qos: .utility
    )
    private var stateMachine = DialogObservationStateMachine()
    private var observers: [pid_t: AXObserver] = [:]
    private var observerRegistrations: [pid_t: [AXNotificationRegistration]] = [:]
    private var dialogObserverPID: pid_t?
    private var dialogObserverRegistrations: [AXNotificationRegistration] = []
    private var observedApplications: [pid_t: AXUIElement] = [:]
    private var observedDialogElement: AXUIElement?
    private var workspaceToken: NSObjectProtocol?
    private var pollTimer: Timer?
    private var scanWorkItem: DispatchWorkItem?
    private var pendingVisibleWindowFallback = false
    private var pollCount = 0
    private var scanInFlight = false
    private var rescanRequested = false
    private var lastFocusSnapshot: DialogFocusSnapshot?
    private var focusUnavailableSince: Date?
    private var lastReportedStatus: FileDialogMonitorStatus?
    private var currentDetections: [String: DetectedFileDialog] = [:]

    init(
        detector: FileDialogDetector = FileDialogDetector(),
        processDiscovery: DialogProcessDiscovery = DialogProcessDiscovery()
    ) {
        self.detector = detector
        self.processDiscovery = processDiscovery
    }

    deinit {
        stop()
    }

    func start() {
        guard workspaceToken == nil else { return }

        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            self?.frontmostApplicationChanged(application)
        }

        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        tick()
    }

    func stop() {
        scanWorkItem?.cancel()
        scanWorkItem = nil
        pendingVisibleWindowFallback = false
        rescanRequested = false
        pollTimer?.invalidate()
        pollTimer = nil

        if let workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
            self.workspaceToken = nil
        }

        tearDownObservers()
        currentDetections = [:]
        if stateMachine.attachedDialog != nil {
            onDetach?()
        }
        stateMachine = DialogObservationStateMachine()
        lastFocusSnapshot = nil
        focusUnavailableSince = nil
        lastReportedStatus = nil
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityPermission.isTrusted(promptIfNeeded: true)
        tick()
    }

    func scanNow() {
        scheduleScan(delay: 0, includeVisibleWindowFallback: true)
    }

    private func tick() {
        let trusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
        let permissionCommands = stateMachine.handle(.permissionChanged(trusted))
        execute(permissionCommands, detections: [:])

        guard trusted else {
            reportStatus(.permissionRequired)
            return
        }

        if let application = NSWorkspace.shared.frontmostApplication,
           shouldAdoptAsHost(application),
           stateMachine.observedApplicationPID != Int32(application.processIdentifier) {
            frontmostApplicationChanged(application)
        }

        if stateMachine.observedApplicationPID == nil {
            reportStatus(.waitingForApplication)
        } else {
            pollCount &+= 1
            let focusSnapshot = processDiscovery.focusSnapshot()
            _ = updateFocusAvailability(focusSnapshot)
            let focusChanged = focusSnapshot != lastFocusSnapshot
            lastFocusSnapshot = focusSnapshot
            if focusChanged || (focusSnapshot == nil && stateMachine.attachedDialog != nil) {
                scheduleScan(delay: 0.02, includeVisibleWindowFallback: true)
            } else if pollCount.isMultiple(of: 8) {
                scheduleScan(delay: 0, includeVisibleWindowFallback: true)
            }
        }
    }

    private func frontmostApplicationChanged(_ application: NSRunningApplication) {
        guard shouldAdoptAsHost(application) else {
            scheduleScan(delay: 0.04, includeVisibleWindowFallback: true)
            return
        }

        let commands = stateMachine.handle(
            .frontmostApplicationChanged(Int32(application.processIdentifier))
        )
        execute(commands, detections: [:])
        reportStatus(.watching(application.localizedName ?? "当前应用"))
        scheduleScan(delay: 0.08, includeVisibleWindowFallback: true)
    }

    private func shouldAdoptAsHost(_ application: NSRunningApplication) -> Bool {
        let pid = application.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }

        if processDiscovery.isOpenSavePanelService(application),
           stateMachine.observedApplicationPID != nil {
            return false
        }
        if let attachedPID = stateMachine.attachedDialog?.pid,
           attachedPID == Int32(pid),
           stateMachine.observedApplicationPID != Int32(pid) {
            return false
        }
        return true
    }

    private func scheduleScan(
        delay: TimeInterval,
        includeVisibleWindowFallback: Bool = false
    ) {
        pendingVisibleWindowFallback = pendingVisibleWindowFallback
            || includeVisibleWindowFallback
        scanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performScan()
        }
        scanWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func reportStatus(_ status: FileDialogMonitorStatus) {
        guard lastReportedStatus != status else { return }
        lastReportedStatus = status
        onStatusChange?(status)
    }

    private func performScan() {
        guard AccessibilityPermission.isTrusted(promptIfNeeded: false),
              let hostPID = stateMachine.observedApplicationPID else {
            return
        }
        guard !scanInFlight else {
            rescanRequested = true
            return
        }
        scanInFlight = true

        let includeVisibleWindowFallback = pendingVisibleWindowFallback
        pendingVisibleWindowFallback = false
        let focusSnapshot = processDiscovery.focusSnapshot()
        let focusUnavailableWithinGrace = updateFocusAvailability(focusSnapshot)
        let hostName = NSRunningApplication(processIdentifier: pid_t(hostPID))?.localizedName
            ?? "当前应用"
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let attachedUsesSeparateProcess = stateMachine.attachedDialog.map {
            $0.pid != hostPID
        } ?? false
        let visibleWindows = (includeVisibleWindowFallback || attachedUsesSeparateProcess)
            ? processDiscovery.visibleWindowSnapshots(excluding: ownPID)
            : []
        let candidatePIDs = processDiscovery.candidatePIDs(
            ownPID: ownPID,
            hostPID: pid_t(hostPID),
            attachedPID: stateMachine.attachedDialog.map { pid_t($0.pid) },
            focusedPID: focusSnapshot?.pid,
            visibleWindows: visibleWindows
        )
        let attachedID = stateMachine.attachedDialog?.id
        let ownPanelIsKey = isAttachedPanelKey?() ?? false

        scanQueue.async { [weak self] in
            guard let self else { return }
            var detections: [DetectedFileDialog] = []
            for candidatePID in candidatePIDs {
                let found = self.detector.detectAll(
                    in: candidatePID,
                    hostApplicationPID: pid_t(hostPID),
                    hostApplicationName: hostName
                )
                guard !found.isEmpty else { continue }

                let globallyEligible = found.filter { detection in
                    let hasTopVisibleWindowEvidence = self.hasBoundVisibleWindowEvidence(
                        for: detection,
                        visibleWindows: visibleWindows
                    )
                    return DialogAttachmentFocusPolicy.shouldAttach(
                        dialogPID: detection.observed.pid,
                        hostPID: Int32(detection.session.hostPID),
                        dialogTopLevelID: Int(CFHash(detection.session.originalWindow)),
                        dialogIsLocallyFocused: detection.observed.isFocused,
                        isOnlyCandidateInProcess: found.count == 1,
                        systemFocusedPID: focusSnapshot.map { Int32($0.pid) },
                        systemFocusedTopLevelID: focusSnapshot.map { Int($0.topLevelID) },
                        hasTopVisibleWindowEvidence: hasTopVisibleWindowEvidence
                    )
                }
                if let attachedID {
                    let attached = found.first(where: { $0.observed.id == attachedID })
                    let attachedHasTopVisibleWindowEvidence = attached.map { detection in
                        self.hasBoundVisibleWindowEvidence(
                            for: detection,
                            visibleWindows: visibleWindows
                        )
                    } ?? false
                    if let attached,
                       DialogAttachmentFocusPolicy.shouldKeepAttached(
                        dialogPID: attached.observed.pid,
                        hostPID: Int32(attached.session.hostPID),
                        dialogTopLevelID: Int(CFHash(attached.session.originalWindow)),
                        dialogIsLocallyFocused: attached.observed.isFocused,
                        systemFocusedPID: focusSnapshot.map { Int32($0.pid) },
                        systemFocusedTopLevelID: focusSnapshot.map { Int($0.topLevelID) },
                        ownPID: Int32(ownPID),
                        ownPanelIsKey: ownPanelIsKey,
                        focusUnavailableWithinGrace: focusUnavailableWithinGrace,
                        hasTopVisibleWindowEvidence: attachedHasTopVisibleWindowEvidence
                       ) {
                        detections = [attached]
                    } else {
                        detections = globallyEligible
                    }
                } else if !globallyEligible.isEmpty {
                    detections = globallyEligible
                }
                if !detections.isEmpty { break }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanInFlight = false
                if AccessibilityPermission.isTrusted(promptIfNeeded: false),
                   self.stateMachine.observedApplicationPID == hostPID {
                    let byID = Dictionary(
                        uniqueKeysWithValues: detections.map { ($0.observed.id, $0) }
                    )
                    self.currentDetections = byID
                    let commands = self.stateMachine.handle(
                        .scanCompleted(detections.map(\.observed))
                    )
                    self.execute(commands, detections: byID)
                }
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.scheduleScan(delay: 0)
                }
            }
        }
    }

    private func hasBoundVisibleWindowEvidence(
        for detection: DetectedFileDialog,
        visibleWindows: [DialogVisibleWindowSnapshot]
    ) -> Bool {
        DialogVisibleStackPolicy.isBoundToHost(
            dialogPID: detection.observed.pid,
            hostPID: Int32(detection.session.hostPID),
            dialogFrame: detection.rawFrame,
            confidence: detection.observed.confidence,
            windows: visibleWindows.map { window in
                DialogVisibleWindowEvidence(
                    pid: Int32(window.pid),
                    frame: window.frame,
                    rank: window.rank
                )
            }
        )
    }

    private func execute(
        _ commands: [DialogObservationCommand],
        detections: [String: DetectedFileDialog]
    ) {
        for command in commands {
            switch command {
            case let .observeApplication(pid):
                ensureObserver(for: pid_t(pid))

            case .stopObserving:
                tearDownObservers()

            case let .attach(observed):
                guard let detection = detections[observed.id] else { continue }
                observeDialogElement(
                    detection.session.originalWindow,
                    pid: detection.session.dialogOwnerPID
                )
                onAttach?(detection.session, observed)

            case let .updateAttachment(observed):
                guard let detection = detections[observed.id]
                    ?? currentDetections[observed.id] else {
                    continue
                }
                onUpdate?(detection.session, observed)

            case .detach:
                observedDialogElement = nil
                resetObserversToHost()
                onDetach?()
            }
        }
    }

    private func updateFocusAvailability(
        _ snapshot: DialogFocusSnapshot?
    ) -> Bool {
        if snapshot != nil {
            focusUnavailableSince = nil
            return false
        }
        let now = Date()
        if focusUnavailableSince == nil {
            focusUnavailableSince = now
        }
        return now.timeIntervalSince(focusUnavailableSince ?? now) < 0.6
    }

    private func ensureObserver(for pid: pid_t) {
        guard observers[pid] == nil else { return }

        var newObserver: AXObserver?
        let status = AXObserverCreate(
            pid,
            { _, _, _, refcon in
                guard let refcon else { return }
                let monitor = Unmanaged<FileDialogMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.scheduleScan(
                        delay: 0.06,
                        includeVisibleWindowFallback: true
                    )
                }
            },
            &newObserver
        )
        guard status == .success, let newObserver else { return }

        observers[pid] = newObserver
        let application = AXUIElementCreateApplication(pid)
        observedApplications[pid] = application
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXFocusedUIElementChangedNotification,
            kAXSheetCreatedNotification
        ]
        for notification in notifications {
            let name = notification as CFString
            let result = AXObserverAddNotification(
                newObserver,
                application,
                name,
                refcon
            )
            if result == .success {
                observerRegistrations[pid, default: []].append(
                    AXNotificationRegistration(element: application, notification: name)
                )
            } else if result != .notificationUnsupported {
                Diagnostics.log("observer_add_\(pid)_\(result.rawValue)")
            }
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    private func observeDialogElement(_ dialog: AXUIElement, pid: pid_t) {
        removeDialogRegistrations()
        ensureObserver(for: pid)
        guard let observer = observers[pid] else { return }
        observedDialogElement = dialog
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification
        ]
        for notification in notifications {
            let name = notification as CFString
            let result = AXObserverAddNotification(
                observer,
                dialog,
                name,
                refcon
            )
            if result == .success {
                dialogObserverRegistrations.append(
                    AXNotificationRegistration(element: dialog, notification: name)
                )
                dialogObserverPID = pid
            } else if result != .notificationUnsupported {
                Diagnostics.log("dialog_observer_add_\(pid)_\(result.rawValue)")
            }
        }
    }

    private func resetObserversToHost() {
        removeDialogRegistrations()
        guard let hostPID = stateMachine.observedApplicationPID else {
            tearDownObservers()
            return
        }
        let pid = pid_t(hostPID)
        guard observers.count != 1 || observers[pid] == nil else { return }
        tearDownObservers()
        ensureObserver(for: pid)
    }

    private func tearDownObservers() {
        removeDialogRegistrations()
        for (pid, observer) in observers {
            for registration in observerRegistrations[pid] ?? [] {
                _ = AXObserverRemoveNotification(
                    observer,
                    registration.element,
                    registration.notification
                )
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observers = [:]
        observerRegistrations = [:]
        observedApplications = [:]
        observedDialogElement = nil
    }

    private func removeDialogRegistrations() {
        if let pid = dialogObserverPID,
           let observer = observers[pid] {
            for registration in dialogObserverRegistrations {
                _ = AXObserverRemoveNotification(
                    observer,
                    registration.element,
                    registration.notification
                )
            }
        }
        dialogObserverPID = nil
        dialogObserverRegistrations = []
        observedDialogElement = nil
    }
}
