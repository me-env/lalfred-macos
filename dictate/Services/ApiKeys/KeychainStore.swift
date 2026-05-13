import Foundation
import OSLog
import Foundation
import Security
import os



private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "APIKeyDefaultsStore")


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


struct Keychain {
  let service: String = "fr.lalfred.dictate"

  func set(_ value: String, key: String) {
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
  
  func delete(_ key: String) {
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
