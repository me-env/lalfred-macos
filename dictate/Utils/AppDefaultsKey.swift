import Foundation

enum AppDefaultsKey {
    static let apiKeyElevenLabs = "apiKey.11l"
    static let apiKeyOpenAI = "apiKey.openai"
    static let authToken = "auth.token"
    static let launchAtLogin = "launchAtLogin"
    static let modeState = "savedModeState"
    static let savedSnippets = "savedSnippets"
    static let savedWords = "savedWords"
    static let shortcutModeSwitcher = "shortcut.modeSwitcher"
    static let shortcutToggleRecording = "shortcut.toggleRecording"
    static let shortcutHoldToSpeak = "shortcut.holdToSpeak"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let isSignedIn = "auth.isSignedIn"
    static let accountEmail = "auth.account.email"
    static let accountFirstName = "auth.account.firstName"
    static let accountLastName = "auth.account.lastName"
    static let accountCredits = "auth.account.credits"

    static let modeDefaultApplicationPath = "mode.default.applicationPath"
    static let modeEmailApplicationPath = "mode.email.applicationPath"
    static let modeTerminalApplicationPath = "mode.terminal.applicationPath"

    static let shortcutModeDefaultTrigger = "shortcut.mode.defaultTrigger"
    static let shortcutModeEmailTrigger = "shortcut.mode.emailTrigger"
    static let shortcutModeTerminalTrigger = "shortcut.mode.terminalTrigger"
}
