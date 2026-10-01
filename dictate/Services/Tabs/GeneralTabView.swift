import SwiftUI
import AppKit
import Sparkle


struct GeneralTabView: View {
  @Environment(Shortcuts.self) private var shortcuts
  @Environment(\.sparkleUpdater) private var sparkleUpdater
  @Environment(\.openWindow) private var openWindow
  @State private var activeShortcutEditorID: String?
  @AppStorage(AppDefaultsKey.smartPasteFormatting) private var smartPasteFormatting = true
  @AppStorage(AppDefaultsKey.textInsertionMethod) private var textInsertionMethod = TextInsertionMethod.default

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
      HStack {
        Toggle("Match surrounding text when pasting", isOn: $smartPasteFormatting)
        Spacer()
        Button("Inspect…") {
          openWindow(id: PasteContextInspectorView.windowID)
        }
        .help("See what accessibility exposes in other apps and what pasting would produce there.")
      }
    }
  }

  var advancedSection: some View {
    SectionBoxWithTitle("Advanced", caption: textInsertionMethod.explanation) {
      Picker("Insert text by", selection: $textInsertionMethod) {
        ForEach(TextInsertionMethod.allCases) { method in
          Text(method.title).tag(method)
        }
      }
    }
  }

  var body: some View {
    VStack {
      PreferencesInput()
      TranscriptionSection()
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
        Divider()
        ShortcutInput(
          label: "Retry Last Recording",
          store: shortcuts.retryLastRecording,
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }

      experimentalSection

      advancedSection

      if let sparkleUpdater {
        updatesSection(sparkleUpdater: sparkleUpdater)
      }

      DeveloperSection()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
