import Foundation
import XCTest
@testable import MacListCore

final class LocalIndexMenuPresentationTests: XCTestCase {
    func testDisabledOffersInitialFolderSelectionOnly() {
        let presentation = LocalIndexMenuPresentation(state: .disabled)

        XCTAssertEqual(presentation.statusTitle, "本地索引：未设置")
        XCTAssertEqual(presentation.chooseFoldersTitle, "选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertFalse(presentation.canRebuild)
        XCTAssertFalse(presentation.canClear)
    }

    func testIndexingDisablesConflictingActionsButAllowsClear() {
        let presentation = LocalIndexMenuPresentation(
            state: .indexing(folderCount: 2)
        )

        XCTAssertEqual(presentation.statusTitle, "本地索引：正在建立（2 个文件夹）")
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertFalse(presentation.canChooseFolders)
        XCTAssertFalse(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }

    func testReadyShowsCountsAndEnablesAllActions() {
        let presentation = LocalIndexMenuPresentation(
            state: .ready(
                fileCount: 128,
                folderCount: 2,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        XCTAssertEqual(
            presentation.statusTitle,
            "本地索引：已就绪（128 个文件，2 个文件夹）"
        )
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertTrue(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }

    func testPartialShowsCountsAndKeepsEveryRecoveryActionAvailable() {
        let presentation = LocalIndexMenuPresentation(
            state: .partial(
                fileCount: 96,
                folderCount: 2,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        XCTAssertEqual(
            presentation.statusTitle,
            "本地索引：部分完成（96 个文件，2 个文件夹）"
        )
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertTrue(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }

    func testNeedsRefreshKeepsEveryRecoveryActionAvailable() {
        let presentation = LocalIndexMenuPresentation(
            state: .needsRefresh(folderCount: 2)
        )

        XCTAssertEqual(presentation.statusTitle, "本地索引：需要更新（2 个文件夹）")
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertTrue(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }

    func testNeedsAuthorizationOffersReselectionWithoutUnsafeCacheActions() {
        let presentation = LocalIndexMenuPresentation(state: .needsAuthorization)

        XCTAssertEqual(presentation.statusTitle, "本地索引：需要重新选择文件夹")
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertFalse(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }

    func testFailedOffersReselectionAndClearButNotRebuild() {
        let presentation = LocalIndexMenuPresentation(state: .failed)

        XCTAssertEqual(presentation.statusTitle, "本地索引：操作失败")
        XCTAssertEqual(presentation.chooseFoldersTitle, "重新选择索引文件夹…")
        XCTAssertTrue(presentation.canChooseFolders)
        XCTAssertFalse(presentation.canRebuild)
        XCTAssertTrue(presentation.canClear)
    }
}
