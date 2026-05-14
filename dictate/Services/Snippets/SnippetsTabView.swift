import SwiftUI


struct SnippetsTabView: View {
  @AppStorage(AppDefaultsKey.savedSnippets) private var savedSnippetsData: Data = Data()
  @State private var newKey: String = ""
  @State private var newValue: String = ""
  @State private var newFullMatch = false
  private let inputControlHeight: CGFloat = 32
  
  private var snippets: [Snippet] {
    (try? JSONDecoder().decode([Snippet].self, from: savedSnippetsData)) ?? []
  }
  
  private var sanitizedKey: String {
    normalizeWhitespace(newKey)
  }
  
  private var sanitizedValue: String {
    normalizeWhitespace(newValue)
  }
  
  private var canAddSnippet: Bool {
    !sanitizedKey.isEmpty && !sanitizedValue.isEmpty
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      inputRow
        .padding(.bottom)
      snippetContent
    }
    .padding([.bottom, .horizontal])
  }
  
  private var addButton: some View {
    Button {
      addSnippet()
    } label: {
      Text("Add")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: inputControlHeight)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(canAddSnippet ? Color.accentColor : Color.secondary.opacity(0.35))
        )
    }
    .buttonStyle(.plain)
    .disabled(!canAddSnippet)

  }
  
  private var inputRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .bottom, spacing: 6) {
        InlineInputField(
          title: "Trigger",
          text: $newKey,
          controlHeight: inputControlHeight,
          width: 130,
          onSubmit: addSnippet,
          style: .light
        )

        InlineInputField(
          title: "Replacement",
          text: $newValue,
          controlHeight: inputControlHeight,
          expandToFill: true,
          onSubmit: addSnippet,
          style: .light
        )

        addButton
      }

      Toggle(isOn: $newFullMatch) {
        FullSentenceMatchLabel()
      }
      .toggleStyle(.checkbox)
      .font(.caption)
    }
  }
  
  @ViewBuilder
  private var snippetContent: some View {
    if snippets.isEmpty {
      emptyState
    } else {
      snippetsList
    }
  }
  
  private var emptyState: some View {
    VStack {
      Spacer()
      ContentUnavailableView(
        "No snippets yet",
        systemImage: "text.bubble",
        description: Text("Create quick replacements for common phrases or repeated text.")
      )
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical)
  }
  
  private var snippetsList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(snippets, id: \.self) { snippet in
          SnippetRow(
            snippet: snippet,
            onToggleFullMatch: { isEnabled in
              updateSnippetFullMatch(snippet, fullMatch: isEnabled)
            },
            onRemove: {
              removeSnippet(snippet)
            }
          )
        }
      }
      .padding(.vertical, 2)
    }
    .frame(minHeight: 220)
  }
  
  private func saveSnippets(_ snippets: [Snippet]) {
    savedSnippetsData = (try? JSONEncoder().encode(snippets)) ?? Data()
  }
  
  private func addSnippet() {
    let key = sanitizedKey
    let value = sanitizedValue
    let fullMatch = newFullMatch

    guard !key.isEmpty, !value.isEmpty else { return }

    var current = snippets
    let exists = current.contains {
      $0.key.caseInsensitiveCompare(key) == .orderedSame &&
      $0.value.caseInsensitiveCompare(value) == .orderedSame &&
      $0.fullMatch == fullMatch
    }
    guard !exists else {
      newKey = ""
      newValue = ""
      newFullMatch = false
      return
    }

    current.append(
      Snippet(
        key: key,
        value: value,
        fullMatch: fullMatch
      )
    )
    saveSnippets(current)
    newKey = ""
    newValue = ""
    newFullMatch = false
  }
  
  private func removeSnippet(_ snippet: Snippet) {
    var current = snippets
    current.removeAll(where: { $0 == snippet })
    saveSnippets(current)
  }

  private func updateSnippetFullMatch(
    _ snippet: Snippet,
    fullMatch: Bool
  ) {
    var current = snippets
    guard let index = current.firstIndex(of: snippet) else {
      return
    }

    current[index].fullMatch = fullMatch
    saveSnippets(deduplicatedSnippets(from: current))
  }

  private func deduplicatedSnippets(from snippets: [Snippet]) -> [Snippet] {
    var seen = Set<String>()
    var deduplicated: [Snippet] = []

    for snippet in snippets {
      let identifier = [
        snippet.key.lowercased(),
        snippet.value.lowercased(),
        snippet.fullMatch ? "1" : "0"
      ].joined(separator: "|")

      if seen.insert(identifier).inserted {
        deduplicated.append(snippet)
      }
    }

    return deduplicated
  }
  
  private func normalizeWhitespace(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
