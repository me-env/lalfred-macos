import Foundation

extension Notification.Name {
  static let shortcutCaptureStateDidChange = Notification.Name("shortcutCapture.stateDidChange")
}

enum ShortcutNotificationUserInfoKey {
  static let isCapturing = "shortcutCapture.isCapturing"
}
