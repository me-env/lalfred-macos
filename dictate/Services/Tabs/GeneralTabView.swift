import SwiftUI
import AppKit


struct GeneralTabView: View {
  @State private var activeShortcutEditorID: String?

  @State private var toggleRecordingRecorder = ShortcutRecorder(
    id: AppDefaultsKey.shortcutToggleRecording,
    defaultShortcut: AppDefaultShortcuts.toggleRecording
  )
  @State private var holdToSpeakRecorder = ShortcutRecorder(
    id: AppDefaultsKey.shortcutHoldToSpeak,
    defaultShortcut: AppDefaultShortcuts.holdToSpeak
  )

  var body: some View {
    VStack {
      PreferencesInput()
      SectionBoxWithTitle("Keyboard Shortcuts") {
        ShortcutInput(
          label: "Toggle Recording",
          recorder: toggleRecordingRecorder,
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          recorder: holdToSpeakRecorder,
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
