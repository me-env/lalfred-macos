import Foundation
import OSLog

struct APIKeyDefaultsStore {
  private static let logger = Logger(subsystem: "fr.lalfred.app", category: "APIKey")

  private let account: String
  private let userDefaults: UserDefaults

  init(
    key: String,
    userDefaults: UserDefaults = .standard
  ) {
    self.account = key
    self.userDefaults = userDefaults
    print("[APIKey] init account=\(key)")
  }

  func load() -> String? {
    print("[APIKey] load() account=\(account)")
    if let value = userDefaults.string(forKey: account) {
      print("[APIKey] load() HIT account=\(account) length=\(value.count) suffix=\(value.suffix(4))")
      return value
    }

    print("[APIKey] load() returning nil account=\(account)")
    return nil
  }

  func save(_ apiKey: String) {
    print("[APIKey] save() account=\(account) length=\(apiKey.count) suffix=\(apiKey.suffix(4))")
    userDefaults.set(apiKey, forKey: account)
  }

  @discardableResult
  func remove() -> Bool {
    print("[APIKey] remove() called account=\(account)")
    userDefaults.removeObject(forKey: account)
    if userDefaults.object(forKey: account) != nil {
      Self.logger.error("UserDefaults remove failed for \(account, privacy: .public)")
      return false
    }
    return true
  }
}
