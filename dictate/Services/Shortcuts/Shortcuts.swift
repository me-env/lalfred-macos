import Foundation
import Observation

@Observable
final class Shortcuts {
  let toggleRecording: ShortcutStore
  let holdToSpeak: ShortcutStore
  let retryLastRecording: ShortcutStore

  init() {
    self.toggleRecording = ShortcutStore(key: AppDefaultsKey.shortcutToggleRecording)
    self.holdToSpeak = ShortcutStore(key: AppDefaultsKey.shortcutHoldToSpeak)
    self.retryLastRecording = ShortcutStore(key: AppDefaultsKey.shortcutRetryLastRecording)

    toggleRecording.ensureDefault(AppDefaultShortcuts.toggleRecording)
    holdToSpeak.ensureDefault(AppDefaultShortcuts.holdToSpeak)
  }
}
