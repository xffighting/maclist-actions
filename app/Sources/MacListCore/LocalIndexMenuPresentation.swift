import Foundation

public struct LocalIndexMenuPresentation: Equatable, Sendable {
    public let statusTitle: String
    public let chooseFoldersTitle: String
    public let canChooseFolders: Bool
    public let canRebuild: Bool
    public let canClear: Bool

    public init(state: LocalIndexServiceState) {
        switch state {
        case .disabled:
            statusTitle = "本地索引：未设置"
            chooseFoldersTitle = "选择索引文件夹…"
            canChooseFolders = true
            canRebuild = false
            canClear = false
        case let .indexing(folderCount):
            statusTitle = "本地索引：正在建立（\(folderCount) 个文件夹）"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = false
            canRebuild = false
            canClear = true
        case let .ready(fileCount, folderCount, _):
            statusTitle = "本地索引：已就绪（\(fileCount) 个文件，\(folderCount) 个文件夹）"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = true
            canRebuild = true
            canClear = true
        case let .partial(fileCount, folderCount, _):
            statusTitle = "本地索引：部分完成（\(fileCount) 个文件，\(folderCount) 个文件夹）"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = true
            canRebuild = true
            canClear = true
        case let .needsRefresh(folderCount):
            statusTitle = "本地索引：需要更新（\(folderCount) 个文件夹）"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = true
            canRebuild = true
            canClear = true
        case .needsAuthorization:
            statusTitle = "本地索引：需要重新选择文件夹"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = true
            canRebuild = false
            canClear = true
        case .failed:
            statusTitle = "本地索引：操作失败"
            chooseFoldersTitle = "重新选择索引文件夹…"
            canChooseFolders = true
            canRebuild = false
            canClear = true
        }
    }
}
