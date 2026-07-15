import Foundation

@main
enum LocalIndexMenuPresentationSmoke {
    static func main() {
        assertPresentation(
            .disabled,
            statusTitle: "本地索引：未设置",
            chooseFoldersTitle: "选择索引文件夹…",
            canChooseFolders: true,
            canRebuild: false,
            canClear: false
        )
        assertPresentation(
            .indexing(folderCount: 2),
            statusTitle: "本地索引：正在建立（2 个文件夹）",
            chooseFoldersTitle: "重新选择索引文件夹…",
            canChooseFolders: false,
            canRebuild: false,
            canClear: true
        )
        assertPresentation(
            .ready(
                fileCount: 128,
                folderCount: 2,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            statusTitle: "本地索引：已就绪（128 个文件，2 个文件夹）",
            chooseFoldersTitle: "重新选择索引文件夹…",
            canChooseFolders: true,
            canRebuild: true,
            canClear: true
        )
        assertPresentation(
            .needsRefresh(folderCount: 2),
            statusTitle: "本地索引：需要更新（2 个文件夹）",
            chooseFoldersTitle: "重新选择索引文件夹…",
            canChooseFolders: true,
            canRebuild: true,
            canClear: true
        )
        assertPresentation(
            .needsAuthorization,
            statusTitle: "本地索引：需要重新选择文件夹",
            chooseFoldersTitle: "重新选择索引文件夹…",
            canChooseFolders: true,
            canRebuild: false,
            canClear: false
        )
        assertPresentation(
            .failed,
            statusTitle: "本地索引：操作失败",
            chooseFoldersTitle: "重新选择索引文件夹…",
            canChooseFolders: true,
            canRebuild: false,
            canClear: true
        )
        print("local-index-menu-presentation: ok")
    }

    private static func assertPresentation(
        _ state: LocalIndexServiceState,
        statusTitle: String,
        chooseFoldersTitle: String,
        canChooseFolders: Bool,
        canRebuild: Bool,
        canClear: Bool
    ) {
        let presentation = LocalIndexMenuPresentation(state: state)
        precondition(presentation.statusTitle == statusTitle)
        precondition(presentation.chooseFoldersTitle == chooseFoldersTitle)
        precondition(presentation.canChooseFolders == canChooseFolders)
        precondition(presentation.canRebuild == canRebuild)
        precondition(presentation.canClear == canClear)
    }
}
