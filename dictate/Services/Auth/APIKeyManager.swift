import Foundation
import Observation

/// The BYOK ("bring your own key") providers exposed in the Account tab.
enum APIKeyProvider: String, CaseIterable, Identifiable {
  case elevenLabs
  case openAI

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .elevenLabs:
      return "ElevenLabs"
    case .openAI:
      return "OpenAI (Unused in beta)"
    }
  }

  var defaultsKey: String {
    switch self {
    case .elevenLabs:
      return AppDefaultsKey.apiKeyElevenLabs
    case .openAI:
      return AppDefaultsKey.apiKeyOpenAI
    }
  }
}

/// Owns BYOK state (which providers have a key configured, which one is being
/// edited, the pending value being typed) and brokers all defaults reads/writes
/// for the Account tab. Views don't talk to `APIKeyDefaultsStore` directly.
@MainActor
@Observable
final class APIKeyManager {
  /// Last-4 suffix of the stored key, keyed by provider. Absent => no key set.
  private(set) var configuredKeySuffixes: [APIKeyProvider: String] = [:]

  /// Provider currently being edited via the editor sheet, if any.
  /// Used as the `Item` in `.sheet(item:)`.
  var editingProvider: APIKeyProvider?

  /// The value the user is typing in the editor sheet.
  var pendingAPIKey: String = ""

  @ObservationIgnored private let storeFactory: (APIKeyProvider) -> APIKeyDefaultsStore

  init() {
    self.storeFactory = APIKeyManager.defaultStoreFactory
  }

  static let defaultStoreFactory: (APIKeyProvider) -> APIKeyDefaultsStore = { provider in
    APIKeyDefaultsStore(key: provider.defaultsKey)
  }

  // MARK: - Queries

  func hasKey(for provider: APIKeyProvider) -> Bool {
    configuredKeySuffixes[provider] != nil
  }

  func keySuffix(for provider: APIKeyProvider) -> String? {
    configuredKeySuffixes[provider]
  }

  // MARK: - Actions

  func refresh() {
    print("[AccountTab] refreshAPIKeyStatuses() begin")
    var suffixes: [APIKeyProvider: String] = [:]

    for provider in APIKeyProvider.allCases {
      let loaded = storeFactory(provider).load()
      print("[AccountTab] refresh provider=\(provider.rawValue) loaded=\(loaded == nil ? "nil" : "non-nil(len=\(loaded!.count))")")
      guard let key = loaded else {
        continue
      }

      let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        print("[AccountTab] refresh provider=\(provider.rawValue) trimmed empty, skipping")
        continue
      }

      suffixes[provider] = String(trimmed.suffix(4))
    }

    configuredKeySuffixes = suffixes
    print("[AccountTab] refreshAPIKeyStatuses() end suffixes=\(suffixes.mapValues { $0 })")
  }

  func beginEditing(_ provider: APIKeyProvider) {
    print("[AccountTab] beginEditing provider=\(provider.rawValue)")
    pendingAPIKey = storeFactory(provider).load() ?? ""
    editingProvider = provider
  }

  func cancelEditing() {
    editingProvider = nil
    pendingAPIKey = ""
  }

  /// Saves `pendingAPIKey` for the currently-editing provider. Trims whitespace
  /// and silently no-ops if the trimmed value is empty.
  func saveCurrent() {
    guard let provider = editingProvider else {
      print("[AccountTab] saveCurrent ABORT — no editingProvider")
      return
    }

    let trimmed = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    print("[AccountTab] saveAPIKey provider=\(provider.rawValue) trimmedLength=\(trimmed.count)")
    guard !trimmed.isEmpty else {
      print("[AccountTab] saveAPIKey ABORT — trimmed empty provider=\(provider.rawValue)")
      return
    }

    storeFactory(provider).save(trimmed)
    configuredKeySuffixes[provider] = String(trimmed.suffix(4))
    editingProvider = nil
    pendingAPIKey = ""
    print("[AccountTab] saveAPIKey done provider=\(provider.rawValue) suffix=\(trimmed.suffix(4))")
  }

  func delete(_ provider: APIKeyProvider) {
    print("[AccountTab] deleteKey CLICKED provider=\(provider.rawValue)")
    let ok = storeFactory(provider).remove()
    configuredKeySuffixes[provider] = nil
    print("[AccountTab] deleteKey done provider=\(provider.rawValue) defaultsOK=\(ok)")
  }
}
