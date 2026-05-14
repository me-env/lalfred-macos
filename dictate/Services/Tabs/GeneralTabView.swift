import SwiftUI
import AppKit


struct GeneralTabView: View {
  @Environment(Shortcuts.self) private var shortcuts
  @State private var activeShortcutEditorID: String?

  var body: some View {
    VStack {
      PreferencesInput()
      SectionBoxWithTitle("Keyboard Shortcuts") {
        ShortcutInput(
          label: "Toggle Recording",
          store: shortcuts.toggleRecording,
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          store: shortcuts.holdToSpeak,
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
