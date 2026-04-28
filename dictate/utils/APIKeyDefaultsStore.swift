//
//  APIKeyDefaultsStore.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Foundation
import Security

struct APIKeyDefaultsStore {
  private let service: String
  private let account: String
  private let legacyStore: UserDefaultsCodableStore<String>
  
  init(
    key: String,
    userDefaults: UserDefaults = .standard,
    service: String = Bundle.main.bundleIdentifier ?? "dictate"
  ) {
    self.service = service
    self.account = key
    self.legacyStore = UserDefaultsCodableStore<String>(key: key, userDefaults: userDefaults)
  }
  
  func load() -> String? {
    let query = baseQuery(returnData: true)
    var result: CFTypeRef?
    
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess,
       let data = result as? Data,
       let value = String(data: data, encoding: .utf8) {
      return value
    }
    
    // One-time migration from the old UserDefaults-based storage.
    if let legacyValue = legacyStore.load() {
      save(legacyValue)
      legacyStore.remove()
      return legacyValue
    }
    
    return nil
  }
  
  func save(_ apiKey: String) {
    guard let data = apiKey.data(using: .utf8) else {
      return
    }

    let query = baseQuery()
    let attributes: [String: Any] = [kSecValueData as String: data]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    if updateStatus == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      SecItemAdd(item as CFDictionary, nil)
    }

    legacyStore.remove()
  }
  
  func remove() {
    SecItemDelete(baseQuery() as CFDictionary)
    legacyStore.remove()
  }
  
  private func baseQuery(returnData: Bool = false) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    
    if returnData {
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
    }
    
    return query
  }
}
