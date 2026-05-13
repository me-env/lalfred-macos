import SwiftUI

struct SnippetFullMatchMenuButton: View {
  let isMatchEntireSentenceOnly: Bool
  let onToggleMatchEntireSentenceOnly: (Bool) -> Void

  var body: some View {
    Button {
      onToggleMatchEntireSentenceOnly(!isMatchEntireSentenceOnly)
    } label: {
      Label(
        isMatchEntireSentenceOnly ? "Disable Full Match" : "Enable Full Match",
        systemImage: isMatchEntireSentenceOnly ? "checkmark.circle.fill" : "checkmark.circle"
      )
    }
  }
}

#Preview {
  VStack {
    SnippetFullMatchMenuButton(
      isMatchEntireSentenceOnly: true,
      onToggleMatchEntireSentenceOnly: { _ in }
    )
    .padding()
    
    SnippetFullMatchMenuButton(
      isMatchEntireSentenceOnly: false,
      onToggleMatchEntireSentenceOnly: { _ in }
    )
    .padding()
  }
  
}
