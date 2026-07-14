import Foundation

public enum PrivacyPolicy {
    private static let excludedComponents: Set<String> = [
        ".git", ".svn", ".hg", ".Trash", "node_modules", "DerivedData",
        "Caches", "Cache", "tmp", "Temp"
    ]

    private static let excludedLibrarySections: Set<String> = [
        "Application Support", "Preferences", "Logs", "Cookies",
        "Saved Application State", "WebKit", "HTTPStorages"
    ]

    public static func shouldInclude(
        path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        guard shouldIncludeSpotlightPath(
            path: path,
            homeDirectory: homeDirectory
        ) else {
            return false
        }

        let standardized = URL(fileURLWithPath: path).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        return true
    }

    public static func shouldIncludeSpotlightPath(
        path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let homePath = homeDirectory.standardizedFileURL.path

        guard standardized.path.hasPrefix(homePath + "/") else { return false }

        let relative = String(standardized.path.dropFirst(homePath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard !components.contains(where: excludedComponents.contains) else { return false }
        guard !components.dropLast().contains(where: { $0.hasPrefix(".") }) else { return false }

        if components.first == "Library" {
            let isUserDocumentContainer = standardized.path.contains("/Data/Documents/")
                || standardized.path.contains("/Mail Downloads/")
                || standardized.path.contains("/Mobile Documents/")
                || standardized.path.contains("/CloudStorage/")
            if !isUserDocumentContainer { return false }
            if components.contains(where: excludedLibrarySections.contains) { return false }
        }

        return true
    }

    public static func compactParentPath(
        for path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let home = homeDirectory.standardizedFileURL.path
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") {
            return "~/" + parent.dropFirst(home.count + 1)
        }
        return parent
    }
}
