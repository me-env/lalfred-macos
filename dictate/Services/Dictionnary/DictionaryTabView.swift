import SwiftUI

struct DictionaryTabView: View {
  @State private var words: [String]
  @State private var newWord: String = ""
  @FocusState private var isSearchFocused: Bool

  private let keyTermsStore: KeyTermsStore

  init(keyTermsStore: KeyTermsStore = KeyTermsStore()) {
    self.keyTermsStore = keyTermsStore
    _words = State(initialValue: keyTermsStore.load())
  }
  
  private var sanitizedInput: String {
    newWord.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private var filteredWords: [String] {
    guard !sanitizedInput.isEmpty else {
      return words
    }
    
    return words.filter { word in
      word.localizedCaseInsensitiveContains(sanitizedInput)
    }
  }
  
  private var displayedWords: [String] {
    filteredWords.reversed()
  }
  
  var body: some View {
    VStack(spacing: 10) {
      inputControls
      wordContent
    }
    .padding([.bottom, .horizontal])
  }
  
  private var inputControls: some View {
    GeometryReader { geometry in
      let spacing: CGFloat = 10
      let availableWidth = max(geometry.size.width - spacing, 0)
      let searchFraction: CGFloat = isSearchFocused ? 2.0 / 3.0 : 1.0 / 3.0
      let searchWidth = availableWidth * searchFraction
      let inputWidth = availableWidth - searchWidth
      
      HStack(spacing: spacing) {
        inputField
          .frame(width: inputWidth)
        searchField
          .frame(width: searchWidth)
      }
    }
    .frame(height: 32)
    .animation(.easeInOut(duration: 0.18), value: isSearchFocused)
  }
  
  private var inputField: some View {
    InlineInputField(
      title: "Add a Word",
      text: $newWord,
      onSubmit: addWord,
      style: .light
    )
  }
  
  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      
      TextField("Search words", text: $newWord)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
      
      if !newWord.isEmpty {
        Button {
          newWord = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 32)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(0.35), lineWidth: 1)
    )
  }
  
  @ViewBuilder
  private var wordContent: some View {
    if words.isEmpty {
      emptyState
    } else if filteredWords.isEmpty {
      searchEmptyState
    } else {
      wordList
    }
  }
  
  private var emptyState: some View {
    VStack {
      Spacer()
      ContentUnavailableView(
        "No words yet",
        systemImage: "text.book.closed",
        description: Text("Add names, tools, or jargon you want to transcribe accurately.")
      )
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical)
  }
  
  private var searchEmptyState: some View {
    VStack {
      Spacer()
      ContentUnavailableView(
        "No matches",
        systemImage: "magnifyingglass",
        description: Text("Try another search term.")
      )
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical)
  }
  
  private var wordList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(displayedWords, id: \.self) { word in
          WordRow(word: word) {
            removeWord(word)
          }
        }
      }
      .padding(.vertical, 2)
    }
  }
  
  private func addWord() {
    let trimmed = sanitizedInput
    guard !trimmed.isEmpty else {
      return
    }

    words = keyTermsStore.add(trimmed)
    newWord = ""
  }

  private func removeWord(_ word: String) {
    words = keyTermsStore.remove(word)
  }
}

private struct WordRow: View {
  let word: String
  let onRemove: () -> Void
  @State var hovered: Bool = false
  
  var body: some View {
    HStack(spacing: 10) {
      Text(word)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      RowDeleteButton(
        helpText: "Remove \(word)",
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
        .stroke(.separator.opacity(0.35), lineWidth: 1)
    )
    .onHover(perform: { hovered = $0 })
    .animation(.bouncy, value: hovered)
    .contextMenu {
      RowDeleteMenuButton(title: "Remove", action: onRemove)
    }
  }
}

#Preview {
  DictionaryTabView()
}
