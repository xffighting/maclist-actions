import Foundation

enum Diagnostics {
    static func log(_ event: String) {
        #if DEBUG
        print("MACLIST_EVENT=\(event)")
        fflush(stdout)
        #endif
    }
}
