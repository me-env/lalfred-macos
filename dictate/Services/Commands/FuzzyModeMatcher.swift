import Foundation

enum FuzzyModeMatcher {
  static func topMatches(
    for query: String,
    in suggestions: [ModeDefinition],
    limit: Int = 5
  ) -> [ModeDefinition] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      return Array(suggestions.prefix(limit))
    }

    let ranked = suggestions.compactMap { suggestion -> (ModeDefinition, Int)? in
      guard let score = score(
        query: trimmedQuery,
        candidate: "\(suggestion.title) \(suggestion.id)"
      ) else {
        return nil
      }
      return (suggestion, score)
    }

    return ranked
      .sorted { lhs, rhs in
        if lhs.1 == rhs.1 {
          return lhs.0.title < rhs.0.title
        }
        return lhs.1 > rhs.1
      }
      .prefix(limit)
      .map(\.0)
  }

  private static func score(query: String, candidate: String) -> Int? {
    let queryLower = query.lowercased()
    let candidateLower = candidate.lowercased()
    if candidateLower.hasPrefix(queryLower) {
      return 1_000 - queryLower.count
    }
    if candidateLower.contains(queryLower) {
      return 750 - queryLower.count
    }

    var queryIndex = queryLower.startIndex
    var lastMatchPosition = -1
    var totalGaps = 0
    var matchedCount = 0

    for (position, character) in candidateLower.enumerated() {
      guard queryIndex < queryLower.endIndex else { break }
      if character == queryLower[queryIndex] {
        if lastMatchPosition >= 0 {
          totalGaps += (position - lastMatchPosition - 1)
        }
        lastMatchPosition = position
        matchedCount += 1
        queryIndex = queryLower.index(after: queryIndex)
      }
    }

    guard queryIndex == queryLower.endIndex else { return nil }
    return 500 + (matchedCount * 6) - totalGaps
  }
}
