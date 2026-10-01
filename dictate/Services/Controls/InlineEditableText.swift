import SwiftUI

/// Text that becomes a text field in place when clicked. Hovering tints it and shows a text cursor.
/// Return or clicking elsewhere saves, Escape cancels; an empty or unchanged value is not saved.
struct InlineEditableText: View {
  let text: String
  var font: Font = .body
  var helpText: String = "Click to edit"
  let onCommit: (String) -> Void

  @State private var isEditing = false
  @State private var draft = ""
  @State private var isHovered = false
  @FocusState private var isFocused: Bool

  var body: some View {
    content
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.primary.opacity(backgroundOpacity))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color.accentColor.opacity(isEditing ? 0.6 : 0), lineWidth: 1)
      )
      .animation(.easeInOut(duration: 0.12), value: isHovered)
  }

  @ViewBuilder
  private var content: some View {
    if isEditing {
      TextField("", text: $draft)
        .textFieldStyle(.plain)
        .font(font)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onSubmit(commit)
        .onExitCommand(perform: cancel)
        .onChange(of: isFocused) { _, focused in
          if !focused {
            commit()
          }
        }
    } else {
      Text(text)
        .font(font)
        .lineLimit(1)
        .truncationMode(.tail)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .pointerStyle(.horizontalText)
        .onTapGesture(perform: beginEditing)
        .help(helpText)
    }
  }

  private var backgroundOpacity: Double {
    if isEditing { return 0.06 }
    return isHovered ? 0.08 : 0
  }

  private func beginEditing() {
    draft = text
    isHovered = false
    isEditing = true
  }

  private func commit() {
    guard isEditing else { return }
    isEditing = false

    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != text else { return }
    onCommit(trimmed)
  }

  private func cancel() {
    isEditing = false
  }
}

#Preview {
  @Previewable @State var text = "Click me to edit"

  InlineEditableText(text: text) { text = $0 }
    .frame(width: 240, alignment: .leading)
    .padding()
}
