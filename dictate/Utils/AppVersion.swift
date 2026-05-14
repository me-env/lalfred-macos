import Foundation

enum AppVersion {
  static var name: String {
    Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
  }

  static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
  }
}
