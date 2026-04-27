# Dictate

A lightweight macOS app that lets you dictate text into any application using a global keyboard shortcut and the [ElevenLabs](https://elevenlabs.io) speech-to-text API.

## Features

- **Global hotkey** — trigger recording from anywhere on your Mac (default: `⌃⌥Space`)
- **Customisable shortcut** — click the shortcut badge in the app to record a new key combination
- **Auto-paste** — transcribed text is pasted directly into the focused field of any app
- **Secure key storage** — your ElevenLabs API key is stored in the macOS Keychain

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+
- An [ElevenLabs API key](https://elevenlabs.io)

## Getting started

1. Clone the repo and open `dictate.xcodeproj` in Xcode.
2. Build and run the app (`⌘R`).
3. On first launch, grant the two required permissions in the **Permissions** section:
   - **Microphone** — for capturing audio.
   - **Accessibility** — for registering the global hotkey and pasting into other apps.
4. Paste your ElevenLabs API key into the **11L API Key** field and press Return.
5. Press the hotkey from any app to start recording. Press it again to stop and insert the transcription.

## Project structure

```
dictate/
├── dictateApp.swift              # App entry point & runtime coordinator
├── ContentView.swift             # Tab-based main UI (Home / Models)
├── APIKeyInput.swift             # API key field (persisted to Keychain)
├── views/
│   ├── ShortcutInput.swift       # Hotkey recorder UI
│   └── PermissionsInput.swift    # Microphone & Accessibility permission UI
├── utils/
│   ├── GlobalHotKeyMonitor.swift # Carbon hot-key registration
│   ├── AccessibilityPermissionService.swift
│   ├── ShortcutDefaultsStore.swift
│   ├── APIKeyDefaultsStore.swift
│   ├── UserDefaultsCodableStore.swift
│   ├── ShortcutModifiers+SwiftUI.swift
│   ├── Shortcut+Carbon.swift
│   ├── ShortcutNotifications.swift
│   └── KeyCode.swift
└── types/
    └── Shortcut.swift            # Shortcut model
```

## License

MIT
