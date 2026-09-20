import SwiftUI
import AppKit
import Sparkle


struct GeneralTabView: View {
  @Environment(Shortcuts.self) private var shortcuts
  @Environment(\.sparkleUpdater) private var sparkleUpdater
  @State private var activeShortcutEditorID: String?
  @AppStorage(AppDefaultsKey.smartPasteFormatting) private var smartPasteFormatting = true

  func updatesSection(sparkleUpdater: SPUUpdater) -> some View {
    SectionBoxWithTitle("Updates") {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Stay on the latest version of L'Alfred.")
          Text("Currently version \(AppVersion.version)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        CheckForUpdatesView(updater: sparkleUpdater)
      }
    }
  }

  var experimentalSection: some View {
    SectionBoxWithTitle(
      "Experimental",
      caption: "Uses accessibility to read what sits before the cursor. Heuristic, so it gets abbreviations and quotes wrong sometimes."
    ) {
      Toggle("Match surrounding text when pasting", isOn: $smartPasteFormatting)
    }
  }

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

      experimentalSection

      if let sparkleUpdater {
        updatesSection(sparkleUpdater: sparkleUpdater)
      }

      DeveloperSection()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
