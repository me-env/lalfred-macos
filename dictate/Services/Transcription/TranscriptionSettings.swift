import Foundation


enum TranscriptionProvider: String, CaseIterable, Identifiable {
  case scribeV2 = "scribe_v2"
  case voxtral = "voxtral_mini"

  static let defaultProvider: TranscriptionProvider = .scribeV2

  var id: String { rawValue }

  nonisolated var displayName: String {
    switch self {
    case .scribeV2:
      return "Scribe v2"
    case .voxtral:
      return "Voxtral"
    }
  }

  /// The service whose API key this model needs.
  var apiKeyProvider: APIKeyProvider {
    switch self {
    case .scribeV2:
      return .elevenLabs
    case .voxtral:
      return .mistral
    }
  }

  var languageCodeKey: String {
    switch self {
    case .scribeV2:
      return AppDefaultsKey.languageCodeScribeV2
    case .voxtral:
      return AppDefaultsKey.languageCodeVoxtral
    }
  }

  /// Nil when the provider has no transcript edit.
  var transcriptEditKey: String? {
    switch self {
    case .scribeV2:
      return AppDefaultsKey.transcriptEditScribeV2
    case .voxtral:
      return nil
    }
  }

  /// How many dictionary words a request carries at most; the most recently added ones are kept.
  var maxKeyterms: Int {
    switch self {
    case .scribeV2:
      return KeyTermsStore.maxRequestTerms
    case .voxtral:
      return 100
    }
  }

  /// Why this provider doesn't receive a dictionary term; nil when the term is sent.
  nonisolated func ignoredKeytermReason(_ term: String) -> String? {
    switch self {
    case .scribeV2:
      return nil
    case .voxtral:
      let hasSeparator = term.contains { $0.isWhitespace || $0 == "," }
      return hasSeparator ? "Ignored by \(displayName): only single words without commas are supported." : nil
    }
  }

  /// Codes offered in the main language picker.
  var languageCodes: [String] {
    switch self {
    case .scribeV2:
      return TranscriptionLanguages.codes
    case .voxtral:
      return TranscriptionLanguages.voxtralCodes
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

  static func load(from userDefaults: UserDefaults = .standard) -> TranscriptionSettings {
    let provider = userDefaults.string(forKey: AppDefaultsKey.transcriptionProvider)
      .flatMap(TranscriptionProvider.init(rawValue:)) ?? .defaultProvider

    let transcriptEdit = (provider.transcriptEditKey.flatMap(userDefaults.string(forKey:)) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(transcriptEditMaxLength)

    let languageCode = userDefaults.string(forKey: provider.languageCodeKey) ?? ""

    return TranscriptionSettings(
      provider: provider,
      transcriptEdit: transcriptEdit.isEmpty ? nil : String(transcriptEdit),
      languageCode: languageCode.isEmpty ? nil : languageCode
    )
  }
}

/// ISO 639-1 codes offered in settings; Scribe accepts more, these are the common ones.
nonisolated enum TranscriptionLanguages {
  static let codes: [String] = [
    "af", "ar", "bg", "bn", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
    "fi", "fr", "ga", "gl", "gu", "he", "hi", "hr", "hu", "id", "is", "it", "ja", "kn", "ko",
    "lt", "lv", "ml", "mr", "ms", "nl", "no", "pa", "pl", "pt", "ro", "ru", "sk", "sl", "sr",
    "sv", "sw", "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh",
  ].sorted { displayName(for: $0).localizedCompare(displayName(for: $1)) == .orderedAscending }

  /// The languages Voxtral Mini Transcribe supports.
  static let voxtralCodes: [String] = [
    "ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh",
  ].sorted { displayName(for: $0).localizedCompare(displayName(for: $1)) == .orderedAscending }

  static func displayName(for code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
  }
}
