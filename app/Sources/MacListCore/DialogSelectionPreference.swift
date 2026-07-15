import Foundation

/// Persists how MacList should finish a selection in the host file dialog.
///
/// A missing or unrecognized value intentionally falls back to the streamlined
/// flow: select the candidate and confirm the original file dialog.
public final class DialogSelectionPreference {
    public static let defaultKey = "fileDialogSelectionMode"
    public static let defaultMode: DialogSelectionMode = .selectAndConfirm

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = DialogSelectionPreference.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public var mode: DialogSelectionMode {
        get {
            guard let rawValue = userDefaults.string(forKey: key),
                  let storedMode = DialogSelectionMode(rawValue: rawValue) else {
                return Self.defaultMode
            }
            return storedMode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: key)
        }
    }

    @discardableResult
    public func toggle() -> DialogSelectionMode {
        let nextMode: DialogSelectionMode = mode == .selectAndConfirm
            ? .selectOnly
            : .selectAndConfirm
        mode = nextMode
        return nextMode
    }
}
