import Foundation

/// The realtime models were removed. Someone who had one selected moves to the batch model of the
/// same service, so they keep using the API key they set up, along with their Scribe settings.
enum RemovedRealtimeModels {
  private static let replacements: [String: TranscriptionProvider] = [
    "scribe_v2_realtime": .scribeV2,
    "voxtral_mini_realtime": .voxtral,
  ]

  /// Settings that only the realtime models read, mapped to their Scribe v2 equivalent (nil: dropped).
  private static let settingReplacements: [String: String?] = [
    "transcription.scribeV2Realtime.languageCode": AppDefaultsKey.languageCodeScribeV2,
    "transcription.scribeV2Realtime.transcriptEdit": AppDefaultsKey.transcriptEditScribeV2,
    "transcription.scribeV2Realtime.secondaryLanguages": nil,
  ]

  static func migrate(in userDefaults: UserDefaults = .standard) {
    migrateSelectedModel(in: userDefaults)
    migrateSettings(in: userDefaults)
  }

  private static func migrateSelectedModel(in userDefaults: UserDefaults) {
    guard let saved = userDefaults.string(forKey: AppDefaultsKey.transcriptionProvider),
          let replacement = replacements[saved] else { return }
    userDefaults.set(replacement.rawValue, forKey: AppDefaultsKey.transcriptionProvider)
  }

  /// A value already set for Scribe v2 wins over the realtime one.
  private static func migrateSettings(in userDefaults: UserDefaults) {
    for (oldKey, newKey) in settingReplacements {
      guard let value = userDefaults.string(forKey: oldKey) else { continue }
      if let newKey, (userDefaults.string(forKey: newKey) ?? "").isEmpty {
        userDefaults.set(value, forKey: newKey)
      }
      userDefaults.removeObject(forKey: oldKey)
    }
  }
}
