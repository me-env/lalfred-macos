import Foundation
import OSLog
import Foundation
import Security
import os


private nonisolated let logger = Logger(subsystem: "fr.lalfred.dictate", category: "APIKeyDefaultsStore")


struct KeychainStore {
  private let key: String
  private let keychain: Keychain = .init()
  
  init(key: String) {
    self.key = key
  }
  
  func load() -> String? {
    if let value = keychain.get(self.key) {
      return value
    }
    return nil
  }
  
  func save(_ value: String?) {
    if let value = value {
      keychain.set(value, key: self.key)
    } else {
      keychain.delete(self.key)
    }
  }
  
  func remove() {
    keychain.delete(self.key)
  }
}


nonisolated struct Keychain {
  let service: String = "fr.lalfred.dictate"

  /// Unit tests run inside the app, whose launch reads API keys. With the real Keychain, an
  /// unsigned test build makes macOS ask for the password every run, and tests could touch
  /// the user's keys. They get a store in memory instead.
  private let memory: InMemoryKeychain? = AppEnvironment.isRunningTests ? .shared : nil

  func set(_ value: String, key: String) {
    if let memory { return memory.set(value, key: key) }
    let data = value.data(using: .utf8)!
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status != errSecSuccess {
      logger.error("Keychain set failed for \(key): \(status)")
    }
  }
  
  func get(_ key: String) -> String? {
    if let memory { return memory.get(key) }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    if status != errSecSuccess {
      logger.error("Keychain get failed for \(key): \(status)")
      return nil
    }
    guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
      return nil
    }
    return str
  }
  
  /// Checks that an item exists without fetching and decrypting its value.
  func contains(_ key: String) -> Bool {
    if let memory { return memory.get(key) != nil }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status != errSecSuccess && status != errSecItemNotFound {
      logger.error("Keychain contains failed for \(key): \(status)")
    }
    return status == errSecSuccess
  }

  func deleteAll() {
    if let memory { return memory.deleteAll() }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      logger.error("Keychain deleteAll failed: \(status)")
    }
  }
  
  func delete(_ key: String) {
    if let memory { return memory.delete(key) }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      logger.error("Keychain delete failed for \(key): \(status)")
    }
  }
}


/// The Keychain while unit tests run, see ``AppEnvironment/isRunningTests``.
nonisolated final class InMemoryKeychain: @unchecked Sendable {
  static let shared = InMemoryKeychain()

  private let lock = NSLock()
  private var items: [String: String] = [:]

  func set(_ value: String, key: String) { lock.withLock { items[key] = value } }
  func get(_ key: String) -> String? { lock.withLock { items[key] } }
  func delete(_ key: String) { lock.withLock { items[key] = nil } }
  func deleteAll() { lock.withLock { items.removeAll() } }
}
