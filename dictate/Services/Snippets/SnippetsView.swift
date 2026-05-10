import SwiftUI

private let fullSentenceMatchToggleTitle = "Full match"

struct Snippet: Hashable, Decodable, Encodable, Equatable {
  var key: String
  var value: String
  var matchEntireSentenceOnly: Bool
  
  init(
    key: String,
    value: String,
    matchEntireSentenceOnly: Bool = false
  ) {
    self.key = key
    self.value = value
    self.matchEntireSentenceOnly = matchEntireSentenceOnly
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    value = try container.decode(String.self, forKey: .value)
    matchEntireSentenceOnly = try container.decodeIfPresent(Bool.self, forKey: .matchEntireSentenceOnly) ?? false
  }
}


struct SnippetsTabView: View {
  @AppStorage(AppDefaultsKey.savedSnippets) private var savedSnippetsData: Data = Data()
  @State private var newKey: String = ""
  @State private var newValue: String = ""
  @State private var newMatchEntireSentenceOnly = false
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

      Toggle(isOn: $newMatchEntireSentenceOnly) {
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
            onToggleMatchEntireSentenceOnly: { isEnabled in
              updateSnippetMatchMode(snippet, matchEntireSentenceOnly: isEnabled)
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
    let matchEntireSentenceOnly = newMatchEntireSentenceOnly

    guard !key.isEmpty, !value.isEmpty else { return }

    var current = snippets
    let exists = current.contains {
      $0.key.caseInsensitiveCompare(key) == .orderedSame &&
      $0.value.caseInsensitiveCompare(value) == .orderedSame &&
      $0.matchEntireSentenceOnly == matchEntireSentenceOnly
    }
    guard !exists else {
      newKey = ""
      newValue = ""
      newMatchEntireSentenceOnly = false
      return
    }

    current.append(
      Snippet(
        key: key,
        value: value,
        matchEntireSentenceOnly: matchEntireSentenceOnly
      )
    )
    saveSnippets(current)
    newKey = ""
    newValue = ""
    newMatchEntireSentenceOnly = false
  }
  
  private func removeSnippet(_ snippet: Snippet) {
    var current = snippets
    current.removeAll(where: { $0 == snippet })
    saveSnippets(current)
  }

  private func updateSnippetMatchMode(
    _ snippet: Snippet,
    matchEntireSentenceOnly: Bool
  ) {
    var current = snippets
    guard let index = current.firstIndex(of: snippet) else {
      return
    }

    current[index].matchEntireSentenceOnly = matchEntireSentenceOnly
    saveSnippets(deduplicatedSnippets(from: current))
  }

  private func deduplicatedSnippets(from snippets: [Snippet]) -> [Snippet] {
    var seen = Set<String>()
    var deduplicated: [Snippet] = []

    for snippet in snippets {
      let identifier = [
        snippet.key.lowercased(),
        snippet.value.lowercased(),
        snippet.matchEntireSentenceOnly ? "1" : "0"
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

private struct SnippetRow: View {
  let snippet: Snippet
  let onToggleMatchEntireSentenceOnly: (Bool) -> Void
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
        isMatchEntireSentenceOnly: snippet.matchEntireSentenceOnly,
        onToggleMatchEntireSentenceOnly: onToggleMatchEntireSentenceOnly
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
        isMatchEntireSentenceOnly: snippet.matchEntireSentenceOnly,
        onToggleMatchEntireSentenceOnly: onToggleMatchEntireSentenceOnly
      )

      Divider()

      RowDeleteMenuButton(title: "Remove snippet", action: onRemove)
    }
  }
}

private struct SnippetConfigurationMenu: View {
  let isVisible: Bool
  let isMatchEntireSentenceOnly: Bool
  let onToggleMatchEntireSentenceOnly: (Bool) -> Void

  var body: some View {
    Menu {
      SnippetFullMatchMenuButton(
        isMatchEntireSentenceOnly: isMatchEntireSentenceOnly,
        onToggleMatchEntireSentenceOnly: onToggleMatchEntireSentenceOnly
      )
    } label: {
      Image(systemName: "slider.horizontal.3")
        .foregroundStyle(Color.secondary)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .opacity(isVisible ? 1 : 0)
    .disabled(!isVisible)
    .help("Configure snippet")
  }
}

private struct SnippetFullMatchMenuButton: View {
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

private struct FullSentenceMatchLabel: View {
  @State private var isTooltipPresented = false
  @State private var isHovered = false

  var body: some View {
    Button {
      isTooltipPresented = true
    } label: {
      HStack(spacing: 4) {
        Text(fullSentenceMatchToggleTitle)

        Image(systemName: "info.circle")
          .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.accentColor.opacity(isHovered ? 0.08 : 0))
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .animation(.easeInOut(duration: 0.12), value: isHovered)
    .popover(isPresented: $isTooltipPresented, arrowEdge: .bottom) {
      FullSentenceMatchTooltipView()
        .frame(width: 420)
        .padding(14)
    }
  }
}

private struct FullSentenceMatchTooltipView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("When to enable full sentence match")
        .font(.headline)

      Text("Use full match for replacement where the text to replace is the entire sentence you dictated")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      FullSentenceUseCaseCard(
        title: "Use case: \"address\"",
        badge: "ON",
        badgeColor: .green,
        primaryLine: "\"address\" -> \"123 rue du blé\"",
        secondaryLine: "\"What's your address ?\" -> \"What's your address ?\"",
        secondaryIcon: "xmark.circle"
      )

      FullSentenceUseCaseCard(
        title: "Use case: \"pro signature\"",
        badge: "OFF",
        badgeColor: .orange,
        primaryLine: "\"pro signature\" -> \"Cyprien Ricque, Dev\"",
        secondaryLine: "\"... regards, pro signature\" -> \"... regards, Cyprien Ricque, Dev\"",
        secondaryIcon: "checkmark.circle"
      )
    }
  }
}

private struct FullSentenceUseCaseCard: View {
  let title: String
  let badge: String
  let badgeColor: Color
  let primaryLine: String
  let secondaryLine: String
  let secondaryIcon: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(title)
          .font(.subheadline.weight(.semibold))

        Text(badge)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(
            Capsule(style: .continuous)
              .fill(badgeColor.opacity(0.16))
          )
          .overlay(
            Capsule(style: .continuous)
              .stroke(badgeColor.opacity(0.4), lineWidth: 1)
          )
      }

      Label(primaryLine, systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(.primary)

      Label(secondaryLine, systemImage: secondaryIcon)
        .font(.caption)
        .foregroundStyle(.primary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}

#Preview {
  SnippetsTabView()
}
