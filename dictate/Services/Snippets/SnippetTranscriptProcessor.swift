import Foundation

struct SnippetTranscriptProcessor {
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func process(transcript: String) -> String {
    let snippets = loadProcessedSnippets()
    guard !snippets.isEmpty else {
      return transcript
    }

    let normalizedText = makeNormalizedText(from: transcript)
    guard !normalizedText.characters.isEmpty else {
      return transcript
    }

    let normalizedTranscript = String(normalizedText.characters)
    if let exactSnippet = snippets.first(where: {
      $0.matchEntireSentenceOnly && $0.normalizedKey == normalizedTranscript
    }) {
      return exactSnippet.replacement
    }

    let inlineSnippets = snippets.filter { !$0.matchEntireSentenceOnly }
    guard !inlineSnippets.isEmpty else {
      return transcript
    }

    let matches = findSnippetMatches(in: normalizedText.characters, snippets: inlineSnippets)
    guard !matches.isEmpty else {
      return transcript
    }

    var result = transcript
    for match in matches.reversed() {
      let startOriginalIndex = normalizedText.originalIndices[match.start]
      let endCharacterOriginalIndex = normalizedText.originalIndices[match.end - 1]
      let endOriginalIndex = result.index(after: endCharacterOriginalIndex)
      result.replaceSubrange(startOriginalIndex..<endOriginalIndex, with: match.replacement)
    }

    return result
  }

  private func loadProcessedSnippets() -> [ProcessedSnippet] {
    let store = UserDefaultsCodableStore<[Snippet]>(
      key: AppDefaultsKey.savedSnippets,
      userDefaults: userDefaults
    )

    guard let snippets = store.load() else {
      return []
    }

    return snippets
      .map { snippet in
        let key = snippet.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = snippet.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessedSnippet(
          rawKey: key,
          replacement: value,
          matchEntireSentenceOnly: snippet.matchEntireSentenceOnly
        )
      }
      .filter { !$0.replacement.isEmpty }
      .compactMap { snippet in
        let normalizedKey = normalizeForMatching(snippet.rawKey)
        guard !normalizedKey.isEmpty else {
          return nil
        }

        return ProcessedSnippet(
          rawKey: snippet.rawKey,
          replacement: snippet.replacement,
          matchEntireSentenceOnly: snippet.matchEntireSentenceOnly,
          normalizedKey: normalizedKey,
          normalizedKeyCharacters: Array(normalizedKey)
        )
      }
      .sorted { lhs, rhs in
        if lhs.normalizedKeyCharacters.count == rhs.normalizedKeyCharacters.count {
          return lhs.rawKey.count > rhs.rawKey.count
        }
        return lhs.normalizedKeyCharacters.count > rhs.normalizedKeyCharacters.count
      }
  }

  private func findSnippetMatches(
    in normalizedText: [Character],
    snippets: [ProcessedSnippet]
  ) -> [SnippetMatch] {
    var matches: [SnippetMatch] = []
    var index = 0

    while index < normalizedText.count {
      var bestMatch: SnippetMatch?

      for snippet in snippets {
        let keyCharacters = snippet.normalizedKeyCharacters
        let keyLength = keyCharacters.count

        guard keyLength > 0 else {
          continue
        }

        guard index + keyLength <= normalizedText.count else {
          continue
        }

        if !matchesPrefix(
          normalizedText,
          at: index,
          prefix: keyCharacters
        ) {
          continue
        }

        if !hasWordBoundaries(
          normalizedText,
          start: index,
          end: index + keyLength
        ) {
          continue
        }

        bestMatch = SnippetMatch(
          start: index,
          end: index + keyLength,
          replacement: snippet.replacement
        )
        break
      }

      if let bestMatch {
        matches.append(bestMatch)
        index = bestMatch.end
      } else {
        index += 1
      }
    }

    return matches
  }

  private func makeNormalizedText(from text: String) -> NormalizedText {
    var characters: [Character] = []
    var originalIndices: [String.Index] = []
    var previousWasWhitespace = true

    var currentIndex = text.startIndex
    while currentIndex < text.endIndex {
      let character = text[currentIndex]
      let folded = String(character)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

      for scalar in folded.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
          characters.append(Character(String(scalar).lowercased()))
          originalIndices.append(currentIndex)
          previousWasWhitespace = false
          continue
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar), !previousWasWhitespace {
          characters.append(" ")
          originalIndices.append(currentIndex)
          previousWasWhitespace = true
        }
      }

      currentIndex = text.index(after: currentIndex)
    }

    while characters.last == " " {
      characters.removeLast()
      originalIndices.removeLast()
    }

    return NormalizedText(characters: characters, originalIndices: originalIndices)
  }

  private func normalizeForMatching(_ value: String) -> String {
    let normalized = makeNormalizedText(from: value)
    return String(normalized.characters)
  }

  private func matchesPrefix(
    _ text: [Character],
    at start: Int,
    prefix: [Character]
  ) -> Bool {
    for offset in 0..<prefix.count where text[start + offset] != prefix[offset] {
      return false
    }

    return true
  }

  private func hasWordBoundaries(
    _ text: [Character],
    start: Int,
    end: Int
  ) -> Bool {
    if start > 0, isWordCharacter(text[start - 1]) {
      return false
    }

    if end < text.count, isWordCharacter(text[end]) {
      return false
    }

    return true
  }

  private func isWordCharacter(_ character: Character) -> Bool {
    character != " "
  }
}

private struct ProcessedSnippet {
  let rawKey: String
  let replacement: String
  let matchEntireSentenceOnly: Bool
  let normalizedKey: String
  let normalizedKeyCharacters: [Character]

  init(
    rawKey: String,
    replacement: String,
    matchEntireSentenceOnly: Bool = false,
    normalizedKey: String = "",
    normalizedKeyCharacters: [Character] = []
  ) {
    self.rawKey = rawKey
    self.replacement = replacement
    self.matchEntireSentenceOnly = matchEntireSentenceOnly
    self.normalizedKey = normalizedKey
    self.normalizedKeyCharacters = normalizedKeyCharacters
  }
}

private struct NormalizedText {
  let characters: [Character]
  let originalIndices: [String.Index]
}

private struct SnippetMatch {
  let start: Int
  let end: Int
  let replacement: String
}
