import SwiftUI

struct Snippet: Hashable, Decodable, Encodable, Equatable {
  var key: String
  var value: String
}

struct SnippetsTabView: View {
  @AppStorage(AppDefaultsKey.savedSnippets) private var savedSnippetsData: Data = Data()
  @State private var newKey: String = ""
  @State private var newValue: String = ""
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
    VStack {
      SectionBox("Snippets", caption: "Add a trigger text and its replacement value.") {
        inputRow
        snippetContent
      }
    }
    .padding()
    .onAppear {
      DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
    }
  }
  
  private var inputRow: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Trigger", text: $newKey)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
        .onSubmit { addSnippet() }
        .frame(width: 130)
        .frame(height: inputControlHeight)
      
      TextField("Replacement", text: $newValue)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
        .onSubmit { addSnippet() }
        .frame(maxWidth: .infinity)
        .frame(height: inputControlHeight)

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
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      Spacer()
    }
  }
  
  private var snippetsList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(snippets, id: \.self) { snippet in
          SnippetRow(snippet: snippet) {
            removeSnippet(snippet)
          }
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
    
    guard !key.isEmpty, !value.isEmpty else { return }
    
    var current = snippets
    let exists = current.contains {
      $0.key.caseInsensitiveCompare(key) == .orderedSame &&
      $0.value.caseInsensitiveCompare(value) == .orderedSame
    }
    guard !exists else {
      newKey = ""
      newValue = ""
      return
    }
    
    current.append(Snippet(key: key, value: value))
    saveSnippets(current)
    newKey = ""
    newValue = ""
  }
  
  private func removeSnippet(_ snippet: Snippet) {
    var current = snippets
    current.removeAll(where: { $0 == snippet })
    saveSnippets(current)
  }
  
  private func normalizeWhitespace(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

private struct SnippetRow: View {
  let snippet: Snippet
  let onRemove: () -> Void
  
  var body: some View {
    HStack(spacing: 10) {
      Text("\(snippet.key) -> \(snippet.value)")
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.tail)
      
      
      Spacer()

      Button(role: .destructive, action: onRemove) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Remove snippet")
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
    .contextMenu {
      Button(role: .destructive, action: onRemove) {
        Label("Remove", systemImage: "trash")
      }
    }
  }
}

#Preview {
  SnippetsTabView()
}
