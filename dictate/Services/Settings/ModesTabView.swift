import SwiftUI

struct ModesTabView: View {
  @State private var activeShortcutEditorID: String?
  @StateObject private var modeCatalog = ModeCatalog()
  @State private var selectedModeID: String?
  
  var modesList: some View {
    let modes = modeCatalog.listModes()
    
    return VStack {
      ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
        Button {
          selectedModeID = mode.id
        } label: {
          ModeListRow(mode: mode)
        }
      }
    }
  }
  
  var body: some View {
    Group {
      if let selectedModeID, let selectedMode = modeCatalog.definition(for: selectedModeID) {
        ModeConfigurationPage(
          mode: selectedMode,
          modeCatalog: modeCatalog,
          activeShortcutEditorID: $activeShortcutEditorID,
          onBack: {
            activeShortcutEditorID = nil
            self.selectedModeID = nil
          }
        )
      } else {
        modesList
      }
    }
    .padding()
    .textFieldStyle(.roundedBorder)
  }
}

private struct ModeListRow: View {
  let mode: ModeDefinition

  private var subtitle: String? {
    let shortcutStore = ShortcutDefaultsStore(key: mode.shortcutStoreKey)
    shortcutStore.ensureDefault(mode.defaultShortcut)
    guard let shortcut = shortcutStore.load() else { return nil }
    return "Shortcut: \(shortcut.toLabels().joined(separator: " "))"
  }

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(mode.title)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.tail)

        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Spacer(minLength: 8)

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }
}

#Preview {
  ModesTabView()
}
