import Foundation

enum AppDefaultsKey {
    static let apiKeyElevenLabs = "apiKey.11l"
    static let apiKeyMistral = "apiKey.mistral"
    static let authToken = "auth.token"
    static let launchAtLogin = "launchAtLogin"
    static let savedSnippets = "savedSnippets"
    static let savedWords = "savedWords"
    static let shortcutToggleRecording = "shortcut.toggleRecording"
    static let shortcutHoldToSpeak = "shortcut.holdToSpeak"
    static let shortcutRetryLastRecording = "shortcut.retryLastRecording"
    static let transcriptionProvider = "transcription.provider"
    static let transcriptEditScribeV2 = "transcription.scribeV2.transcriptEdit"
    static let transcriptEditScribeV2Realtime = "transcription.scribeV2Realtime.transcriptEdit"
    static let languageCodeScribeV2 = "transcription.scribeV2.languageCode"
    static let realtimeLanguageCode = "transcription.scribeV2Realtime.languageCode"
    static let realtimeSecondaryLanguages = "transcription.scribeV2Realtime.secondaryLanguages"
    static let languageCodeVoxtral = "transcription.voxtral.languageCode"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let isSignedIn = "auth.isSignedIn"
    static let accountEmail = "auth.account.email"
    static let accountFirstName = "auth.account.firstName"
    static let accountLastName = "auth.account.lastName"

    static let soundEffectKind = "sound.effectKind"

    static let hasCompletedOnboarding = "ui.hasCompletedOnboarding"
    /// Ids of the ``SmartPasteHint``s the user dismissed (JSON).
    static let dismissedSmartPasteHints = "ui.dismissedSmartPasteHints"

    static let smartPasteFormatting = "experimental.smartPasteFormatting"
    /// ``SmartPasteHint``s found while pasting, per app or website (JSON).
    static let smartPasteHints = "experimental.smartPasteHints"
    static let textInsertionMethod = "advanced.textInsertionMethod"

    static let apiEnvironment = "api.environment"

    static let accountScoped: [String] = [
        isSignedIn,
        accountEmail,
        accountFirstName,
        accountLastName,
    ]
}

