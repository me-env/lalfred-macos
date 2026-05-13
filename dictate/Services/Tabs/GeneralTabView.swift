import SwiftUI
import AppKit


struct GeneralTabView: View {
  @State private var activeShortcutEditorID: String?
  
  var body: some View {
    VStack {
      PreferencesInput()
      SectionBoxWithTitle("Keyboard Shortcuts") {
        ShortcutInput(
          label: "Toggle Recording",
          storeKey: AppDefaultsKey.shortcutToggleRecording,
          defaultShortcut: AppDefaultShortcuts.toggleRecording,
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          storeKey: AppDefaultsKey.shortcutHoldToSpeak,
          defaultShortcut: AppDefaultShortcuts.holdToSpeak,
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
