import AppKit
import MacListCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let initialPermissionPromptKey = "MacListDidRequestAccessibilityPermission"
    private var statusItem: NSStatusItem?
    private var panelController: SearchPanelController?
    private var dialogMonitor: FileDialogMonitor?
    private var monitorStatus: FileDialogMonitorStatus = .waitingForApplication

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let bridge = FileDialogBridge()
        let controller = SearchPanelController(
            provider: SpotlightProvider(),
            dialogBridge: bridge
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

        panelController = controller
        dialogMonitor = monitor
        configureStatusItem()
        rebuildMenu()
        controller.preloadRecentFiles()
        monitor.start()
        requestInitialPermissionIfNeeded(using: monitor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dialogMonitor?.stop()
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestInitialPermissionIfNeeded(using monitor: FileDialogMonitor) {
        guard !AccessibilityPermission.isTrusted(promptIfNeeded: false),
              !UserDefaults.standard.bool(forKey: initialPermissionPromptKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: initialPermissionPromptKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            monitor.requestAccessibilityPermission()
        }
    }
}
