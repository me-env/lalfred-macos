import Observation

@Observable
final class CommandViewModel {
  private let modeCatalog: ModeCatalog

  var query: String = ""
  var suggestions: [ModeDefinition] = []
  var activeModeTitle: String
  @ObservationIgnored var onSubmit: ((String) -> Void)?
  @ObservationIgnored var onDismiss: (() -> Void)?

  init(modeCatalog: ModeCatalog) {
    self.modeCatalog = modeCatalog
    self.activeModeTitle = modeCatalog.currentMode.title
  }

  func filteredSuggestions(for query: String) -> [ModeDefinition] {
    modeCatalog.filteredModes(for: query)
  }

  func reset() {
    query = ""
    suggestions = modeCatalog.filteredModes(for: "")
    activeModeTitle = modeCatalog.currentMode.title
  }
}
