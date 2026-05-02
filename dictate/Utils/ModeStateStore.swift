//
//  ModeStateStore.swift
//  dictate
//

import Foundation
import Combine


struct ModeSuggestion: Identifiable, Hashable, Codable {
  let id: String
  let title: String
  let detail: String
}


@MainActor
final class ModeStateStore: ObservableObject {
  private struct PersistedState: Codable {
    var suggestions: [ModeSuggestion]
    var selectedModeID: String
  }
  
  private let store: UserDefaultsCodableStore<PersistedState>
  @Published private(set) var suggestions: [ModeSuggestion]
  @Published private(set) var selectedModeID: String
  
  init() {
    self.store = UserDefaultsCodableStore(key: AppDefaultsKey.modeState)
    
    let loadedState = self.store.load()
    let defaultSuggestions = Self.defaultSuggestions
    let defaultModeID = defaultSuggestions.first?.id ?? "default"
    self.suggestions = defaultSuggestions
    
    if let loadedState, defaultSuggestions.contains(where: { $0.id == loadedState.selectedModeID }) {
      self.selectedModeID = loadedState.selectedModeID
    } else {
      self.selectedModeID = defaultModeID
    }
    persistState()
  }
  
  var currentMode: ModeSuggestion {
    suggestions.first(where: { $0.id == selectedModeID }) ?? suggestions.first ?? Self.defaultSuggestions[0]
  }
  
  func filteredSuggestions(for query: String, limit: Int = 5) -> [ModeSuggestion] {
    FuzzyModeMatcher.topMatches(for: query, in: suggestions, limit: limit)
  }
  
  @discardableResult
  func selectMode(matching input: String) -> ModeSuggestion? {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else { return nil }
    
    guard let matchedSuggestion = suggestion(matching: trimmedInput) else {
      return nil
    }
    
    selectedModeID = matchedSuggestion.id
    persistState()
    return matchedSuggestion
  }
  
  private func suggestion(matching input: String) -> ModeSuggestion? {
    let normalizedInput = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    return suggestions.first(where: {
      $0.id.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedInput
      || $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedInput
    })
  }
  
  private func persistState() {
    store.save(PersistedState(suggestions: suggestions, selectedModeID: selectedModeID))
  }
  
  static let defaultSuggestions: [ModeSuggestion] = ModeCatalog.definitions.map {
    ModeSuggestion(id: $0.id, title: $0.title, detail: $0.detail)
  }
}
