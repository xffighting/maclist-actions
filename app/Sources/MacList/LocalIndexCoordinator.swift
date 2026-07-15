import AppKit
import MacListCore

@MainActor
final class LocalIndexCoordinator {
    let provider: LocalIndexProvider
    var onStateChange: (() -> Void)?

    private let service: LocalIndexService
    private weak var panelController: SearchPanelController?
    private(set) var state: LocalIndexServiceState = .disabled

    convenience init() {
        let provider = LocalIndexProvider()
        self.init(
            provider: provider,
            service: LocalIndexService(provider: provider)
        )
    }

    init(provider: LocalIndexProvider, service: LocalIndexService) {
        self.provider = provider
        self.service = service
    }

    var menuPresentation: LocalIndexMenuPresentation {
        LocalIndexMenuPresentation(state: state)
    }

    func bind(panelController: SearchPanelController) {
        self.panelController = panelController
    }

    func bootstrap() {
        Task { @MainActor [weak self, service] in
            await service.bootstrap()
            guard let self else { return }
            await synchronizeFromService(refreshSearch: true)
        }
    }

    func chooseFolders() {
        guard menuPresentation.canChooseFolders else { return }

        let panel = NSOpenPanel()
        panel.title = "选择 MacList 可以搜索的文件夹"
        panel.message = "只会保存文件名、路径和修改时间；不会读取文件正文。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.canCreateDirectories = false

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            Task { @MainActor [weak self] in
                await self?.applySelectedFolders(urls)
            }
        }
    }

    func rebuild() {
        guard menuPresentation.canRebuild else { return }
        state = .indexing(folderCount: configuredFolderCount)
        notifyStateChange()
        Task { @MainActor [weak self, service] in
            await service.rebuild()
            guard let self else { return }
            await synchronizeFromService(refreshSearch: true)
        }
    }

    func confirmAndClear() {
        guard menuPresentation.canClear else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清空本地索引？"
        alert.informativeText = "会删除这台 Mac 上保存的文件名、路径、修改时间和文件夹授权信息，不会删除任何原文件。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor [weak self, service] in
            do {
                try await service.clearAll()
            } catch {
                // The service exposes a fail-closed state. No path or query is logged.
            }
            guard let self else { return }
            await synchronizeFromService(refreshSearch: true)
        }
    }

    func cancel() {
        Task { [service] in
            await service.cancelRebuild()
        }
    }

    private func applySelectedFolders(_ urls: [URL]) async {
        do {
            let bookmarks = try urls.map { try AuthorizedFolderBookmark.create(for: $0) }
            state = .indexing(folderCount: bookmarks.count)
            notifyStateChange()
            try await service.replaceAuthorizedFolders(bookmarks)
            await synchronizeFromService(refreshSearch: true)
        } catch {
            await synchronizeFromService(refreshSearch: false)
            presentFolderSelectionError()
        }
    }

    private func synchronizeFromService(refreshSearch: Bool) async {
        state = await service.state
        if refreshSearch {
            panelController?.refreshLocalIndex()
        }
        notifyStateChange()
    }

    private func notifyStateChange() {
        onStateChange?()
    }

    private var configuredFolderCount: Int {
        switch state {
        case let .indexing(folderCount),
             let .needsRefresh(folderCount):
            return folderCount
        case let .ready(_, folderCount, _):
            return folderCount
        case .disabled, .needsAuthorization, .failed:
            return 0
        }
    }

    private func presentFolderSelectionError() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "未能使用所选文件夹"
        alert.informativeText = "请选择更具体、当前可读取的资料文件夹。系统目录、整个用户目录和普通 Library 目录不会被建立索引。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
