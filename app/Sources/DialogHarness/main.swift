import AppKit

final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let resultLabel = NSTextField(labelWithString: "等待选择文件")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in self?.openPanel() }
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacList Dialog Harness"
        window.center()

        let title = NSTextField(labelWithString: "标准文件选择窗口验收")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let explanation = NSTextField(
            wrappingLabelWithString: "文件窗口出现后，按 ⌥Space 搜索。成功时，这里会显示系统窗口真正返回的文件路径。"
        )
        explanation.translatesAutoresizingMaskIntoConstraints = false
        explanation.textColor = .secondaryLabelColor

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.lineBreakMode = .byTruncatingMiddle
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let button = NSButton(title: "重新打开文件窗口", target: self, action: #selector(openPanelAction))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded

        guard let content = window.contentView else { return }
        [title, explanation, resultLabel, button].forEach(content.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),

            explanation.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            explanation.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            explanation.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),

            resultLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            resultLabel.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 22),

            button.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            button.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 24)
        ])

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    @objc private func openPanelAction() {
        openPanel()
    }

    private func openPanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择一个测试文件"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                self.resultLabel.stringValue = url.path
                print("MACLIST_HARNESS_SELECTED=\(url.path)")
            } else {
                self.resultLabel.stringValue = "用户取消或尚未完成"
                print("MACLIST_HARNESS_CANCELLED")
            }
        }
    }
}

let application = NSApplication.shared
let delegate = HarnessDelegate()
application.delegate = delegate
application.run()
