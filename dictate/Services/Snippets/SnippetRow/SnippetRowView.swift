import SwiftUI


struct SnippetRow: View {
  let snippet: Snippet
  let onEditKey: (String) -> Void
  let onEditValue: (String) -> Void
  let onToggleFullMatch: (Bool) -> Void
  let onRemove: () -> Void
  @State var hovered: Bool = false

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        InlineEditableText(
          text: snippet.key,
          font: .system(.body, design: .serif),
          helpText: "Click to edit the trigger",
          onCommit: onEditKey
        )
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)

        Text("→")
          .font(.system(.body, design: .serif))
          .foregroundStyle(.secondary)

        InlineEditableText(
          text: snippet.value,
          font: .system(.body, design: .serif),
          helpText: "Click to edit the replacement",
          onCommit: onEditValue
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      SnippetFullMatchToggle(
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
    .padding(.horizontal, 6)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(0.85), lineWidth: 1)
    )
    .onHover(perform: { hovered = $0 })
    .animation(.easeInOut(duration: 0.15), value: hovered)
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
  VStack(spacing: 8) {
    SnippetRow(
      snippet: .init(key: "address", value: "123 rue du blé", fullMatch: true),
      onEditKey: { _ in },
      onEditValue: { _ in },
      onToggleFullMatch: { _ in },
      onRemove: {}
    )
    SnippetRow(
      snippet: .init(key: "pro signature", value: "Cyprien Ricque, Dev"),
      onEditKey: { _ in },
      onEditValue: { _ in },
      onToggleFullMatch: { _ in },
      onRemove: {}
    )
  }
  .padding()
}
