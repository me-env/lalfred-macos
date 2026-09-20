import Foundation
import Observation

enum APIKeyProvider: String, CaseIterable, Identifiable {
  case elevenLabs

  var id: String { rawValue }

  var displayName: String {
    return providerToName[self] ?? "Unknown"
  }

  var key: String {
    return providerToName[self] ?? "Unknown"
  }
}

let providerToName: [APIKeyProvider: String] = [
  .elevenLabs: "ElevenLabs"
]

let providerToKey: [APIKeyProvider: String] = [
  .elevenLabs: AppDefaultsKey.apiKeyElevenLabs
]


@MainActor
@Observable
final class APIKeyViewModel {
  var editingProvider: APIKeyProvider?
  var refreshToken = UUID()
  let keychain = Keychain()


  // MARK: - Queries
  
  func getApiKey(for provider: APIKeyProvider) -> String? {
    keychain.get(provider.key)
  }

  func hasKey(for provider: APIKeyProvider) -> Bool {
    getApiKey(for: provider) != nil
  }

  func keySuffix(for provider: APIKeyProvider) -> String? {
    if let apiKey = getApiKey(for: provider) {
      return String(apiKey.suffix(4))
    }
    return nil
  }

  // MARK: - Actions
  func beginEditing(_ provider: APIKeyProvider) {
    editingProvider = provider
  }

  func cancelEditing() {
    editingProvider = nil
  }

  func save(_ apiKey: String, for provider: APIKeyProvider) {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    keychain.set(trimmed, key: provider.key)
    refreshToken = UUID()

    editingProvider = nil
  }

  func delete(_ provider: APIKeyProvider) {
    keychain.delete(provider.key)
    refreshToken = UUID()
  }
}
