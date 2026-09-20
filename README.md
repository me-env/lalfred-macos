# L'Alfred

Just dictation, done right.

A native macOS app that turns speech into text in any application. Press a
global hotkey, talk, and the transcription is pasted into whatever field you
were in. Transcription runs on the [ElevenLabs Scribe](https://elevenlabs.io/speech-to-text)
API with your own key — there is no proxy in between.

## Features

- **Global hotkey** — start and stop recording from any app (default: `⌃⌥Space`)
- **Auto-paste** — text lands in the focused field, no clipboard juggling
- **Bring your own key** — your ElevenLabs key is stored in the macOS Keychain
- **Custom dictionary** — key terms, names and jargon that should transcribe correctly
- **Snippets** — rewrite recognised phrases into canonical text

## Install

Download the latest signed build:

```
https://api.dictate.lalfred.ai/releases/download/latest
```

Builds are signed with a Developer ID, notarized by Apple, and update
themselves in place via Sparkle.

## Requirements

- macOS 14 Sonoma or later
- An [ElevenLabs API key](https://elevenlabs.io)

## Build from source

Requires Xcode 15+.

```sh
git clone git@github.com:me-env/lalfred-macos.git
cd lalfred-macos
open dictate.xcodeproj
```

Build and run with `⌘R`. On first launch grant the two permissions the app
asks for:

- **Microphone** — to capture audio
- **Accessibility** — to register the global hotkey and paste into other apps

Then paste your ElevenLabs API key into the API key field and press Return.

## Layout

```
dictate/
├── App/          # Entry point, hotkey monitors, dictation state machine
├── Providers/    # ElevenLabs Scribe client
├── Services/     # Feature modules (transcription, snippets, dictionary, auth, …)
├── Updater/      # Sparkle integration
└── Utils/
```

## License

GPLv3 — see [LICENSE](LICENSE).
