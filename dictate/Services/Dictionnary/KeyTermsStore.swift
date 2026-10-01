import Foundation

struct KeyTermsStore {
  static let maxTermLength = 50

  static let maxRequestTerms = 1000
  
  private let store: UserDefaultsCodableStore<[String]>
  
  init(userDefaults: UserDefaults = .standard) {
    store = UserDefaultsCodableStore<[String]>(
      key: AppDefaultsKey.savedWords,
      userDefaults: userDefaults
    )
  }

  func load() -> [String] {
    sanitize(store.load() ?? [])
  }

  func save(_ terms: [String]) {
    store.save(sanitize(terms))
  }

  func add(_ term: String) -> [String] {
    var terms = load()
    terms.append(term)
    let sanitizedTerms = sanitize(terms)
    store.save(sanitizedTerms)
    return sanitizedTerms
  }

  func remove(_ term: String) -> [String] {
    let terms = load().filter { $0 != term }
    store.save(terms)
    return terms
  }
  
  /// Replaces `term` in place. Returns nil, leaving the list unchanged, when `newTerm` is empty,
  /// too long, or already in the list.
  func rename(_ term: String, to newTerm: String) -> [String]? {
    let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= Self.maxTermLength else { return nil }

    let terms = load()
    let isDuplicate = terms.contains { $0 != term && $0.lowercased() == trimmed.lowercased() }
    guard !isDuplicate else { return nil }

    let renamed = terms.map { $0 == term ? trimmed : $0 }
    store.save(renamed)
    return renamed
  }

  func sanitize(_ terms: [String]) -> [String] {
    var seen = Set<String>()
    
    return terms
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { $0.count <= Self.maxTermLength }
      .filter {
        let normalized = $0.lowercased()
        if seen.contains(normalized) {
          return false
        }
        seen.insert(normalized)
        return true
      }
  }
  
  func keyTermsForRequest() -> [String] {
    Array(load().suffix(Self.maxRequestTerms))
  }
}
