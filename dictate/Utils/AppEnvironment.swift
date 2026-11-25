import Foundation


nonisolated enum AppEnvironment {
  /// Unit tests run inside the app (it's their host). Anything that would touch the user's
  /// real data or prompt them (Keychain, on-device database) checks this and stays in memory.
  /// Swift Testing exit-test children only get `XCTestBundlePath` (test harness for crash reproduction).
  static let isRunningTests = ["XCTestConfigurationFilePath", "XCTestBundlePath"]
    .contains { ProcessInfo.processInfo.environment[$0] != nil }
}
