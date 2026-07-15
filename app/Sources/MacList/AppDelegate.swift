import AppKit
import MacListCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: SearchPanelController?
    private var dialogMonitor: FileDialogMonitor?
    private var localIndexCoordinator: LocalIndexCoordinator?
    private var monitorStatus: FileDialogMonitorStatus = .waitingForApplication
    private let selectionPreference = DialogSelectionPreference()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let bridge = FileDialogBridge()
        let indexCoordinator = LocalIndexCoordinator()
        let controller = SearchPanelController(
            provider: SpotlightProvider(),
            localIndexProvider: indexCoordinator.provider,
            dialogBridge: bridge,
            selectionModeProvider: { [weak self] in
                self?.selectionPreference.mode ?? DialogSelectionPreference.defaultMode
            }
        )
        let monitor = FileDialogMonitor()

        monitor.onAttach = { [weak controller] session, dialog in
            controller?.attach(to: session, dialog: dialog)
        }
        monitor.onUpdate = { [weak controller] session, dialog in
            controller?.updateAttachment(to: session, dialog: dialog)
        }
        monitor.onDetach = { [weak controller] in
            controller?.detach()
        }
        monitor.onStatusChange = { [weak self] status in
            self?.monitorStatus = status
            self?.rebuildMenu()
        }
        monitor.isAttachedPanelKey = { [weak controller] in
            controller?.isPanelKeyAndVisible ?? false
        }
        indexCoordinator.bind(panelController: controller)
        indexCoordinator.onStateChange = { [weak self] in
            self?.rebuildMenu()
        }

        panelController = controller
        dialogMonitor = monitor
        localIndexCoordinator = indexCoordinator
        configureStatusItem()
        rebuildMenu()
        controller.preloadRecentFiles()
        indexCoordinator.bootstrap()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dialogMonitor?.stop()
        localIndexCoordinator?.cancel()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.text.magnifyingglass",
            accessibilityDescription: "MacList"
        )
        item.button?.toolTip = "MacList · 文件上传窗口出现时自动搜索"
        statusItem = item
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let status = NSMenuItem(
            title: statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        let selectionStatus = NSMenuItem(
            title: selectionModeStatusTitle,
            action: nil,
            keyEquivalent: ""
        )
        selectionStatus.isEnabled = false
        menu.addItem(selectionStatus)

        let automaticConfirmationItem = NSMenuItem(
            title: "选中文件后自动确认原窗口",
            action: #selector(toggleAutomaticConfirmation),
            keyEquivalent: ""
        )
        automaticConfirmationItem.state = selectionPreference.mode == .selectAndConfirm
            ? .on
            : .off
        menu.addItem(automaticConfirmationItem)

        if !AccessibilityPermission.isTrusted(promptIfNeeded: false) {
            menu.addItem(
                withTitle: "允许自动唤起…",
                action: #selector(requestPermission),
                keyEquivalent: ""
            )
        } else if !AccessibilityPermission.canPostEvents(promptIfNeeded: false) {
            menu.addItem(
                withTitle: "允许控制当前文件窗口…",
                action: #selector(requestPostEventPermission),
                keyEquivalent: ""
            )
        } else {
            menu.addItem(
                withTitle: "重新扫描当前文件窗口",
                action: #selector(scanNow),
                keyEquivalent: ""
            )
        }

        menu.addItem(.separator())
        let indexPresentation = localIndexCoordinator?.menuPresentation
            ?? LocalIndexMenuPresentation(state: .disabled)
        let indexStatus = NSMenuItem(
            title: indexPresentation.statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        indexStatus.isEnabled = false
        menu.addItem(indexStatus)

        let chooseFoldersItem = NSMenuItem(
            title: indexPresentation.chooseFoldersTitle,
            action: #selector(chooseIndexFolders),
            keyEquivalent: ""
        )
        chooseFoldersItem.isEnabled = indexPresentation.canChooseFolders
        menu.addItem(chooseFoldersItem)

        if indexPresentation.canRebuild || indexPresentation.canClear {
            let rebuildItem = NSMenuItem(
                title: "立即更新本地索引",
                action: #selector(rebuildLocalIndex),
                keyEquivalent: ""
            )
            rebuildItem.isEnabled = indexPresentation.canRebuild
            menu.addItem(rebuildItem)

            let clearItem = NSMenuItem(
                title: "清空本地索引…",
                action: #selector(clearLocalIndex),
                keyEquivalent: ""
            )
            clearItem.isEnabled = indexPresentation.canClear
            menu.addItem(clearItem)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MacList", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { item in
            if item.action != nil { item.target = self }
        }
        statusItem.menu = menu
    }

    private var statusTitle: String {
        if AccessibilityPermission.isTrusted(promptIfNeeded: false),
           !AccessibilityPermission.canPostEvents(promptIfNeeded: false) {
            return "自动唤起：需要文件窗口控制权限"
        }
        switch monitorStatus {
        case .permissionRequired:
            return "自动唤起：需要辅助功能权限"
        case let .watching(application):
            return "自动唤起：正在监听 \(application)"
        case .waitingForApplication:
            return "自动唤起：等待文件上传窗口"
        }
    }

    private var selectionModeStatusTitle: String {
        switch selectionPreference.mode {
        case .selectAndConfirm:
            return "回车动作：选中文件并确认原窗口"
        case .selectOnly:
            return "回车动作：只选中文件（手动确认）"
        }
    }

    @objc private func toggleAutomaticConfirmation() {
        selectionPreference.toggle()
        panelController?.updateSelectionModePresentation()
        rebuildMenu()
    }

    @objc private func requestPermission() {
        dialogMonitor?.requestAccessibilityPermission()
        rebuildMenu()
    }

    @objc private func requestPostEventPermission() {
        _ = AccessibilityPermission.requestPostEventPermission()
        rebuildMenu()
    }

    @objc private func scanNow() {
        dialogMonitor?.scanNow()
    }

    @objc private func chooseIndexFolders() {
        localIndexCoordinator?.chooseFolders()
    }

    @objc private func rebuildLocalIndex() {
        localIndexCoordinator?.rebuild()
    }

    @objc private func clearLocalIndex() {
        localIndexCoordinator?.confirmAndClear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

}
