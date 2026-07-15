import AppKit
import Foundation

if CommandLine.arguments.contains("--version") {
    print("MacList 0.3.0-dev")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--doctor") {
    let spotlight = FileManager.default.isExecutableFile(atPath: "/usr/bin/mdfind")
    let accessibility = AccessibilityPermission.isTrusted(promptIfNeeded: false)
    let postEvents = AccessibilityPermission.canPostEvents(promptIfNeeded: false)
    print("{\"spotlight\":\(spotlight),\"accessibility\":\(accessibility),\"postEvents\":\(postEvents)}")
    exit(spotlight ? EXIT_SUCCESS : EXIT_FAILURE)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
