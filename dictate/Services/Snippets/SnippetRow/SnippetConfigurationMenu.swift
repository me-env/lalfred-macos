import SwiftUI

struct SnippetConfigurationMenu: View {
  let isVisible: Bool
  let isMatchEntireSentenceOnly: Bool
  let onToggleMatchEntireSentenceOnly: (Bool) -> Void

  var body: some View {
    Menu {
      SnippetFullMatchMenuButton(
        isMatchEntireSentenceOnly: isMatchEntireSentenceOnly,
        onToggleMatchEntireSentenceOnly: onToggleMatchEntireSentenceOnly
      )
    } label: {
      Image(systemName: "slider.horizontal.3")
        .foregroundStyle(Color.secondary)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .opacity(isVisible ? 1 : 0)
    .disabled(!isVisible)
    .help("Configure snippet")
  }
}

