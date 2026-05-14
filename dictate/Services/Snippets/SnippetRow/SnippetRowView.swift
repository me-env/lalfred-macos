import SwiftUI


struct SnippetRow: View {
  let snippet: Snippet
  let onToggleFullMatch: (Bool) -> Void
  let onRemove: () -> Void
  @State var hovered: Bool = false

  var body: some View {
    HStack(spacing: 10) {
      Text("\(snippet.key)   →   \(snippet.value)")
        .font(.system(.body, design: .serif))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer()

      SnippetConfigurationMenu(
        isVisible: hovered,
        isFullMatch: snippet.fullMatch,
        onToggleFullMatch: onToggleFullMatch
      )

      RowDeleteButton(
        helpText: "Remove snippet",
        isVisible: hovered,
        action: onRemove
      )
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(0.85), lineWidth: 1)
    )
    .onHover(perform: { hovered = $0 })
    .animation(.interpolatingSpring, value: hovered)
    .contextMenu {
      SnippetFullMatchMenuButton(
        isFullMatch: snippet.fullMatch,
        onToggleFullMatch: onToggleFullMatch
      )

      Divider()

      RowDeleteMenuButton(title: "Remove snippet", action: onRemove)
    }
  }
}


#Preview {
  SnippetRow(
    snippet: .init(key: "oui", value: "ah"),
    onToggleFullMatch: { _ in },
    onRemove: {}
  )
  .padding()
}
