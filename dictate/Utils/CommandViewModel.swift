import Observation

@Observable
final class CommandViewModel {
  private let modeCatalog: ModeCatalog

  var query: String = ""
  var suggestions: [ModeDefinition] = []
  @ObservationIgnored var onSubmit: ((String) -> Void)?
  @ObservationIgnored var onDismiss: (() -> Void)?

  init(modeCatalog: ModeCatalog) {
    self.modeCatalog = modeCatalog
  }

  func filteredSuggestions(for query: String) -> [ModeDefinition] {
    modeCatalog.filteredModes(for: query)
  }

  func reset() {
    query = ""
    suggestions = modeCatalog.filteredModes(for: "")
  }
}
