import Foundation
import Observation

enum APIKeyProvider: String, CaseIterable, Identifiable {
  case elevenLabs
  case mistral

  var id: String { rawValue }

  nonisolated var displayName: String {
    switch self {
    case .elevenLabs:
      return "ElevenLabs"
    case .mistral:
      return "Mistral AI"
    }
  }

  var key: String {
    switch self {
    case .elevenLabs:
      return AppDefaultsKey.apiKeyElevenLabs
    case .mistral:
      return AppDefaultsKey.apiKeyMistral
    }
  }

  /// The saved API key, trimmed; throws when none is saved.
  func loadAPIKey() throws -> String {
    let apiKey = (KeychainStore(key: key).load() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      throw TranscriptionError.missingAPIKey(self)
    }
    return apiKey
  }
}


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
