import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.app", category: "APIKeyDefaultsStore")


struct APIKeyDefaultsStore {
  private let account: String
  private let userDefaults: UserDefaults

  init(
    key: String,
    userDefaults: UserDefaults = .standard
  ) {
    self.account = key
    self.userDefaults = userDefaults
  }

  func load() -> String? {
    logger.info("[APIKey] load() account=\(account)")
    if let value = userDefaults.string(forKey: account) {
      logger.info("[APIKey] load() HIT account=\(account) length=\(value.count) suffix=\(value.suffix(4))")
      return value
    }

    logger.info("[APIKey] load() returning nil account=\(account)")
    return nil
  }

  func save(_ apiKey: String) {
    logger.info("[APIKey] save() account=\(account) length=\(apiKey.count) suffix=\(apiKey.suffix(4))")
    userDefaults.set(apiKey, forKey: account)
  }

  @discardableResult
  func remove() -> Bool {
    logger.info("[APIKey] remove() called account=\(account)")
    userDefaults.removeObject(forKey: account)
    if userDefaults.object(forKey: account) != nil {
      logger.error("UserDefaults remove failed for \(account, privacy: .public)")
      return false
    }
    return true
  }
}
