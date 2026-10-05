import Foundation


nonisolated enum AppEnvironment {
  /// Unit tests run inside the app (it's their host). Anything that would touch the user's
  /// real data or prompt them (Keychain, on-device database) checks this and stays in memory.
  static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
