import SwiftUI


struct ModeSwitcherInputView: View {
  @Binding var query: String
  let suggestions: [ModeDefinition]
  let activeModeTitle: String
  let onSubmit: (String) -> Void
  let onDismiss: () -> Void
  
  @FocusState private var isFocused: Bool
  @State private var selectedIndex = 0
  
  var textInput: some View {
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
      .onMoveCommand(perform: handleMoveCommand)
      .padding(.all, 8)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.white.opacity(0.1))
      }
  }
    
  var activeModeIndicator: some View {
    HStack() {
      Spacer()
      HStack(spacing: 0) {
        Circle()
          .fill(.mint)
          .frame(width: 5, height: 5)
          .padding(.horizontal, 8)
        
        Text(activeModeTitle)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
          .padding(.trailing, 8)
          .padding(.vertical, 4)
      }
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.white.opacity(0.1))
      }
    }
    .padding(.horizontal, 2)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      activeModeIndicator
      textInput

      FuzzySuggestionList(
        suggestions: suggestions,
        selectedIndex: selectedIndex
      )
    }
    .onAppear {
      selectedIndex = 0
      isFocused = true
    }
    .onChange(of: query) { _, _ in
      selectedIndex = 0
    }
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
  let suggestions: [ModeDefinition]
  let selectedIndex: Int
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
        HStack {
          Text(suggestion.title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
          Spacer()
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(index == selectedIndex ? .white.opacity(0.16) : .clear)
        }
      }
    }
  }
}


#Preview("Mode Switcher Input") {
  let sampleModes = Array(ModeCatalog.defaultModes.prefix(3))
  ModeSwitcherInputView(
    query: .constant("sum"),
    suggestions: sampleModes,
    activeModeTitle: "Default",
    onSubmit: { _ in },
    onDismiss: {}
  )
  .frame(width: 300)
  .padding()
}
