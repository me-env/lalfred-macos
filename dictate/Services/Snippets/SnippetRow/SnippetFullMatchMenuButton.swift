import SwiftUI

struct SnippetFullMatchMenuButton: View {
  let isFullMatch: Bool
  let onToggleFullMatch: (Bool) -> Void

  var body: some View {
    Button {
      onToggleFullMatch(!isFullMatch)
    } label: {
      Label(
        isFullMatch ? "Disable Full Match" : "Enable Full Match",
        systemImage: isFullMatch ? "checkmark.circle.fill" : "checkmark.circle"
      )
    }
  }
}

#Preview {
  VStack {
    SnippetFullMatchMenuButton(
      isFullMatch: true,
      onToggleFullMatch: { _ in }
    )
    .padding()
    
    SnippetFullMatchMenuButton(
      isFullMatch: false,
      onToggleFullMatch: { _ in }
    )
    .padding()
  }
  
}
