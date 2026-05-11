import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "APIKeyDefaultsStore")


struct APIKeyStore {
  private let account: String
  private let userDefaults: UserDefaults = .standard

  init(key: String) {
    self.account = key
  }

  func load() -> String? {
    if let value = userDefaults.string(forKey: account) {
      return value
    }

    return nil
  }

  func save(_ apiKey: String) {
    userDefaults.set(apiKey, forKey: account)
  }

  @discardableResult
  func remove() -> Bool {
    userDefaults.removeObject(forKey: account)
    if userDefaults.object(forKey: account) != nil {
      return false
    }
    return true
  }
}
