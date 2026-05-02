import SwiftUI


struct ModeSwitcherInputView: View {
  @Binding var query: String
  let suggestions: [ModeSuggestion]
  let onSubmit: (String) -> Void
  let onDismiss: () -> Void
  
  @FocusState private var isFocused: Bool
  @State private var selectedIndex = 0
  
    
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Mode…", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .tint(.white)
        .focused($isFocused)
        .onSubmit {
          submitSelectedValue()
        }
        .onExitCommand {
          onDismiss()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.1))
        }
      
      FuzzySuggestionList(
        suggestions: suggestions,
        selectedIndex: selectedIndex
      )
    }
    //    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      selectedIndex = 0
      isFocused = true
    }
    .onChange(of: query) { _, _ in
      selectedIndex = 0
    }
//    .onMoveCommand(perform: handleMoveCommand)
  }
  
  private func submitSelectedValue() {
    let selectedSuggestion = suggestions.indices.contains(selectedIndex)
    ? suggestions[selectedIndex].title
    : nil
    let rawInput = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalValue = selectedSuggestion ?? (rawInput.isEmpty ? "" : rawInput)
    guard !finalValue.isEmpty else { return }
    onSubmit(finalValue)
  }
  
  private func handleMoveCommand(_ direction: MoveCommandDirection) {
    guard !suggestions.isEmpty else { return }
    switch direction {
    case .down:
      selectedIndex = min(selectedIndex + 1, suggestions.count - 1)
    case .up:
      selectedIndex = max(selectedIndex - 1, 0)
    default:
      break
    }
  }
}

private struct FuzzySuggestionList: View {
  let suggestions: [ModeSuggestion]
  let selectedIndex: Int
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
        HStack(spacing: 6) {
          Text(suggestion.title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
          Text(suggestion.detail)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(index == selectedIndex ? .white.opacity(0.16) : .clear)
        }
      }
    }
  }
}


#Preview("Mode Switcher Input") {
  ModeSwitcherInputView(
    query: .constant("sum"),
    suggestions: [
      .init(id: "summary", title: "Summarize", detail: "Condense into concise points"),
      .init(id: "summary-bullets", title: "Summary Bullet Points", detail: "Return bullets only"),
      .init(id: "email", title: "Email Draft", detail: "Format as a professional email")
    ],
    onSubmit: { _ in },
    onDismiss: {}
  )
  .frame(width: 300, height: 140)
  .padding()
}
