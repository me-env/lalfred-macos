import SwiftUI

struct SnippetConfigurationMenu: View {
  let isVisible: Bool
  let isFullMatch: Bool
  let onToggleFullMatch: (Bool) -> Void

  var body: some View {
    Menu {
      SnippetFullMatchMenuButton(
        isFullMatch: isFullMatch,
        onToggleFullMatch: onToggleFullMatch
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

