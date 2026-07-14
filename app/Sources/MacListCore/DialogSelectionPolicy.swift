import Foundation

public enum DialogSelectionMode: String, Codable, Sendable {
    case selectAndConfirm
    case selectOnly
}

public enum DialogBridgeStep: String, Codable, CaseIterable, Sendable {
    case restoreDialogFocus
    case openGoToFolder
    case locateWritablePathField
    case writeAbsolutePath
    case confirmPath
    case verifyExactSelection
    case confirmSelection
}

public enum DialogSelectionError: Error, Equatable, LocalizedError, Sendable {
    case accessibilityPermissionRequired
    case postEventPermissionRequired
    case noFileDialog
    case unsupportedDialog
    case emptyPath
    case fileMissing(String)
    case directoryNotAllowed(String)
    case bridgeTimedOut(DialogBridgeStep)
    case selectionCouldNotBeVerified(String)
    case operationCancelled
    case systemFailure(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "请先允许 MacList 使用“辅助功能”，再重新打开文件上传窗口。"
        case .postEventPermissionRequired:
            return "请允许 MacList 控制当前文件窗口，然后再试一次。"
        case .noFileDialog:
            return "正在等待微信或邮件的文件上传窗口。"
        case .unsupportedDialog:
            return "这个上传窗口暂不支持自动选择；原窗口没有被关闭或修改。"
        case .emptyPath:
            return "没有可提交的文件路径。"
        case let .fileMissing(path):
            return "文件已移动或删除：\(path)"
        case let .directoryNotAllowed(path):
            return "请选择文件而不是文件夹：\(path)"
        case let .bridgeTimedOut(step):
            return "文件窗口响应超时（\(step.displayName)），原窗口仍保持打开。"
        case let .selectionCouldNotBeVerified(path):
            return "已定位到文件，但无法确认它已被精确选中：\(path)"
        case .operationCancelled:
            return "原文件窗口已经关闭或切换，本次操作已取消。"
        case let .systemFailure(message):
            return "系统文件窗口操作失败：\(message)"
        }
    }
}

public struct FileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public struct ValidatedFile: Equatable, Sendable {
    public let url: URL
    public let identity: FileIdentity?

    public init(url: URL, identity: FileIdentity?) {
        self.url = url
        self.identity = identity
    }
}

public extension DialogBridgeStep {
    var displayName: String {
        switch self {
        case .restoreDialogFocus: return "恢复原窗口"
        case .openGoToFolder: return "打开前往文件夹"
        case .locateWritablePathField: return "查找路径输入框"
        case .writeAbsolutePath: return "写入文件路径"
        case .confirmPath: return "确认路径"
        case .verifyExactSelection: return "核对选中文件"
        case .confirmSelection: return "确认上传文件"
        }
    }
}

public enum DialogSelectionPolicy {
    public static func validateFileURL(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try validateFile(url, fileManager: fileManager).url
    }

    public static func validateFile(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> ValidatedFile {
        guard url.isFileURL, !url.path.isEmpty else {
            throw DialogSelectionError.emptyPath
        }

        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw DialogSelectionError.fileMissing(standardized.path)
        }
        guard !isDirectory.boolValue else {
            throw DialogSelectionError.directoryNotAllowed(standardized.path)
        }
        let canonical = standardized.resolvingSymlinksInPath()
        let attributes = try? fileManager.attributesOfItem(atPath: canonical.path)
        let device = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        let identity = device.flatMap { device in
            inode.map { FileIdentity(device: device, inode: $0) }
        }
        return ValidatedFile(url: canonical, identity: identity)
    }

    public static func plan(for mode: DialogSelectionMode) -> [DialogBridgeStep] {
        var steps: [DialogBridgeStep] = [
            .restoreDialogFocus,
            .openGoToFolder,
            .locateWritablePathField,
            .writeAbsolutePath,
            .confirmPath,
            .verifyExactSelection
        ]
        if mode == .selectAndConfirm {
            steps.append(.confirmSelection)
        }
        return steps
    }
}
