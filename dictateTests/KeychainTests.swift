import Foundation
import Testing
@testable import L_Alfred


struct KeychainTests {
  /// If this fails, tests read the real Keychain and macOS prompts for the password.
  @Test func testsUseTheInMemoryKeychain() {
    #expect(AppEnvironment.isRunningTests)
  }

  @Test func storesAndDeletesInMemory() {
    let keychain = Keychain()
    let key = "test.\(UUID().uuidString)"
    #expect(keychain.get(key) == nil)
    keychain.set("secret", key: key)
    #expect(keychain.get(key) == "secret")
    #expect(keychain.contains(key))
    keychain.delete(key)
    #expect(!keychain.contains(key))
  }
}
