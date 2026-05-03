import Foundation

extension Notification.Name {
    static let shortcutDidChange = Notification.Name("shortcut.didChange")
    static let shortcutCaptureStateDidChange = Notification.Name("shortcutCapture.stateDidChange")
}

enum ShortcutNotificationUserInfoKey {
    static let isCapturing = "shortcutCapture.isCapturing"
}
