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
