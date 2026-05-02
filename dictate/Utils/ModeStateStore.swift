//
//  ModeStateStore.swift
//  dictate
//

import Foundation
import Combine

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

        if let loadedState, !loadedState.suggestions.isEmpty {
            self.suggestions = loadedState.suggestions
            let selectedID = loadedState.selectedModeID
            self.selectedModeID = loadedState.suggestions.contains(where: { $0.id == selectedID })
                ? selectedID
                : defaultModeID
            persistState()
        } else {
            self.suggestions = defaultSuggestions
            self.selectedModeID = defaultModeID
            persistState()
        }
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

    static let defaultSuggestions: [ModeSuggestion] = [
        ModeSuggestion(id: "default", title: "Default", detail: "Standard dictation"),
        ModeSuggestion(id: "rewrite", title: "Rewrite", detail: "Improve grammar and clarity"),
        ModeSuggestion(id: "summarize", title: "Summarize", detail: "Condense into concise points"),
        ModeSuggestion(id: "email", title: "Email Draft", detail: "Format as a professional email"),
        ModeSuggestion(id: "translate-fr", title: "Translate French", detail: "Output in French"),
        ModeSuggestion(id: "translate-es", title: "Translate Spanish", detail: "Output in Spanish")
    ]
}
