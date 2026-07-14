import ApplicationServices

enum AccessibilityPermission {
    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func canPostEvents(promptIfNeeded: Bool) -> Bool {
        if CGPreflightPostEventAccess() { return true }
        return promptIfNeeded ? CGRequestPostEventAccess() : false
    }

    static func requestPostEventPermission() -> Bool {
        CGRequestPostEventAccess()
    }
}
