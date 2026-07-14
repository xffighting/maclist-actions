import AppKit
import MacListCore
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: SearchPanelController?
    private var dialogMonitor: FileDialogMonitor?
    private var monitorStatus: FileDialogMonitorStatus = .waitingForApplication
    private let logger = Logger(
        subsystem: "com.xffighting.maclist",
        category: "SearchPermission"
    )
    private var isCheckingSearchFolderAccess = false
    private var searchFolderAccessSummary = "文件搜索：常用位置访问权限未检查"

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
        let searchStatus = NSMenuItem(
            title: searchFolderAccessSummary,
            action: nil,
            keyEquivalent: ""
        )
        searchStatus.isEnabled = false
        menu.addItem(searchStatus)
        let searchPermissionItem = NSMenuItem(
            title: isCheckingSearchFolderAccess
                ? "正在检查文件夹权限…"
                : "检查常用文件夹与云盘访问权限…",
            action: #selector(requestSearchFolderAccess),
            keyEquivalent: ""
        )
        searchPermissionItem.isEnabled = !isCheckingSearchFolderAccess
        menu.addItem(searchPermissionItem)

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

    @objc private func requestSearchFolderAccess() {
        guard !isCheckingSearchFolderAccess else { return }
        isCheckingSearchFolderAccess = true
        searchFolderAccessSummary = "文件搜索：正在检查常用位置访问权限"
        rebuildMenu()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let commonFolders = [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs",
                isDirectory: true
            )
        ]
        let cloudStorage = home.appendingPathComponent(
            "Library/CloudStorage",
            isDirectory: true
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fileManager = FileManager.default
            let cloudDomainListing = try? fileManager.contentsOfDirectory(
                at: cloudStorage,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let cloudDomains = cloudDomainListing?.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            } ?? []
            let folders = commonFolders + cloudDomains
            let accessibleCount = folders.reduce(into: 0) { count, folder in
                if (try? fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) != nil {
                    count += 1
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingSearchFolderAccess = false
                if accessibleCount == 0 {
                    self.searchFolderAccessSummary = "文件搜索：未能访问常用位置，可能尚未授权"
                } else if cloudDomainListing == nil {
                    self.searchFolderAccessSummary = "文件搜索：可访问 \(accessibleCount) 个位置；云盘待授权"
                } else {
                    self.searchFolderAccessSummary = "文件搜索：当前可访问 \(accessibleCount) 个位置"
                }
                self.logger.notice(
                    "common folder access available=\(accessibleCount, privacy: .public) cloudChecked=\(cloudDomainListing != nil, privacy: .public)"
                )
                self.panelController?.preloadRecentFiles()
                self.rebuildMenu()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestInitialPermissionIfNeeded(using monitor: FileDialogMonitor) {
        guard !AccessibilityPermission.isTrusted(promptIfNeeded: false) else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            monitor.requestAccessibilityPermission()
        }
    }
}
