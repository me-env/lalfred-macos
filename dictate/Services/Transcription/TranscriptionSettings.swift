import Foundation


enum TranscriptionProvider: String, CaseIterable, Identifiable {
  case scribeV2 = "scribe_v2"
  case scribeV2Realtime = "scribe_v2_realtime"

  static let defaultProvider: TranscriptionProvider = .scribeV2

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .scribeV2:
      return "Scribe v2"
    case .scribeV2Realtime:
      return "Scribe v2 Realtime"
    }
  }

  var languageCodeKey: String {
    switch self {
    case .scribeV2:
      return AppDefaultsKey.languageCodeScribeV2
    case .scribeV2Realtime:
      return AppDefaultsKey.realtimeLanguageCode
    }
  }

  var transcriptEditKey: String {
    switch self {
    case .scribeV2:
      return AppDefaultsKey.transcriptEditScribeV2
    case .scribeV2Realtime:
      return AppDefaultsKey.transcriptEditScribeV2Realtime
    }
  }
}

/// The transcription options saved in settings, read when a transcription starts.
struct TranscriptionSettings {
  static let transcriptEditMaxLength = 2000

  let provider: TranscriptionProvider
  /// Natural-language instruction applied to the transcript; nil when unset.
  let transcriptEdit: String?
  /// Main language of the selected provider; nil lets the model detect it.
  let languageCode: String?
  let realtimeSecondaryLanguages: [String]

  static func load(from userDefaults: UserDefaults = .standard) -> TranscriptionSettings {
    let provider = userDefaults.string(forKey: AppDefaultsKey.transcriptionProvider)
      .flatMap(TranscriptionProvider.init(rawValue:)) ?? .defaultProvider

    let transcriptEdit = (userDefaults.string(forKey: provider.transcriptEditKey) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(transcriptEditMaxLength)

    let languageCode = userDefaults.string(forKey: provider.languageCodeKey) ?? ""
    let secondaryLanguages = TranscriptionLanguages.decode(
      userDefaults.string(forKey: AppDefaultsKey.realtimeSecondaryLanguages) ?? ""
    )

    return TranscriptionSettings(
      provider: provider,
      transcriptEdit: transcriptEdit.isEmpty ? nil : String(transcriptEdit),
      languageCode: languageCode.isEmpty ? nil : languageCode,
      realtimeSecondaryLanguages: secondaryLanguages.filter { $0 != languageCode }
    )
  }
}

/// ISO 639-1 codes offered in settings; Scribe accepts more, these are the common ones.
enum TranscriptionLanguages {
  static let codes: [String] = [
    "af", "ar", "bg", "bn", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
    "fi", "fr", "ga", "gl", "gu", "he", "hi", "hr", "hu", "id", "is", "it", "ja", "kn", "ko",
    "lt", "lv", "ml", "mr", "ms", "nl", "no", "pa", "pl", "pt", "ro", "ru", "sk", "sl", "sr",
    "sv", "sw", "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh",
  ].sorted { displayName(for: $0).localizedCompare(displayName(for: $1)) == .orderedAscending }

  static func displayName(for code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
  }

  /// Languages are stored as a comma-separated list of codes.
  static func decode(_ rawValue: String) -> [String] {
    rawValue.split(separator: ",").map(String.init).filter { !$0.isEmpty }
  }

  static func encode(_ codes: [String]) -> String {
    codes.joined(separator: ",")
  }
}
