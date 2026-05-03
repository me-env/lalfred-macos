import Foundation
import Combine

struct ModeDefinition: Identifiable, Hashable, Codable {
  let id: String
  let title: String
  let shortcutStoreKey: String
  let defaultShortcut: Shortcut
  let additionalVocabulary: [String]
  var llmInstruction: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case shortcutStoreKey
    case defaultShortcut = "fallbackShortcut"
    case additionalVocabulary
    case llmInstruction
  }
}

struct PromptPreset: Identifiable, Hashable, Codable {
  let id: String
  let title: String
  let instruction: String?
}

enum ModePromptSelection: Hashable, Codable {
  case preset(String)
  case custom(String)

  private enum CodingKeys: String, CodingKey {
    case type
    case presetID
    case prompt
  }

  private enum SelectionType: String, Codable {
    case preset
    case custom
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(SelectionType.self, forKey: .type)
    switch type {
    case .preset:
      self = .preset(try container.decode(String.self, forKey: .presetID))
    case .custom:
      self = .custom(try container.decode(String.self, forKey: .prompt))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .preset(presetID):
      try container.encode(SelectionType.preset, forKey: .type)
      try container.encode(presetID, forKey: .presetID)
    case let .custom(prompt):
      try container.encode(SelectionType.custom, forKey: .type)
      try container.encode(prompt, forKey: .prompt)
    }
  }
}


@MainActor
final class ModeCatalog: ObservableObject {
  private struct PersistedState: Codable {
    var selectedModeID: String
    var promptSelectionsByModeID: [String: ModePromptSelection]
  }

  private struct LegacyPersistedState: Codable {
    var modes: [ModeDefinition]
    var selectedModeID: String
  }
  
  private struct LegacyModeState: Codable {
    var selectedModeID: String
  }
  
  private let store = UserDefaultsCodableStore<PersistedState>(key: AppDefaultsKey.modeCatalog)
  private let legacyCatalogStore = UserDefaultsCodableStore<LegacyPersistedState>(key: AppDefaultsKey.modeCatalog)
  private let legacyStore = UserDefaultsCodableStore<LegacyModeState>(key: AppDefaultsKey.modeState)
  
  @Published private(set) var modes: [ModeDefinition]
  @Published private(set) var selectedModeID: String
  @Published private(set) var promptSelectionsByModeID: [String: ModePromptSelection]
  
  init() {
    let persistedState = store.load()
    let legacyPersistedState = persistedState == nil ? legacyCatalogStore.load() : nil
    let requestedSelectedModeID = persistedState?.selectedModeID
    ?? legacyPersistedState?.selectedModeID
    ?? legacyStore.load()?.selectedModeID
    ?? Self.defaultModes.first?.id
    ?? "default"
    
    let resolvedModes = Self.defaultModes
    
    let resolvedSelectedModeID = resolvedModes.contains(where: { $0.id == requestedSelectedModeID })
    ? requestedSelectedModeID
    : (resolvedModes.first?.id ?? "default")
    
    let resolvedPromptSelectionsByModeID = persistedState?.promptSelectionsByModeID
    ?? Self.migratePromptSelections(from: legacyPersistedState?.modes ?? [])
    
    self.modes = resolvedModes
    self.selectedModeID = resolvedSelectedModeID
    self.promptSelectionsByModeID = resolvedPromptSelectionsByModeID
    
    persistState()
  }
  
  var currentMode: ModeDefinition {
    let mode = modes.first(where: { $0.id == selectedModeID }) ?? modes.first ?? Self.defaultModes[0]
    return resolvedModeDefinition(for: mode)
  }
  
  func listModes() -> [ModeDefinition] {
    modes
  }
  
  func definition(for modeID: String) -> ModeDefinition? {
    modes.first(where: { $0.id == modeID })
  }
  
  func filteredModes(for query: String, limit: Int = 5) -> [ModeDefinition] {
    FuzzyModeMatcher.topMatches(for: query, in: modes, limit: limit)
  }
  
  @discardableResult
  func selectMode(matching input: String) -> ModeDefinition? {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else { return nil }
    
    guard let matchedMode = mode(matching: trimmedInput) else {
      return nil
    }
    
    selectedModeID = matchedMode.id
    persistState()
    return matchedMode
  }
  
  @discardableResult
  func selectMode(id modeID: String) -> ModeDefinition? {
    guard let mode = definition(for: modeID) else { return nil }
    selectedModeID = mode.id
    persistState()
    return mode
  }
  
  func saveModes(_ modes: [ModeDefinition]) {
    guard !modes.isEmpty else { return }
    self.modes = modes
    
    if !modes.contains(where: { $0.id == selectedModeID }) {
      selectedModeID = modes[0].id
    }
    
    persistState()
  }

  func listPromptPresets(for modeID: String) -> [PromptPreset] {
    Self.defaultPromptPresets
  }

  func promptSelection(for modeID: String) -> ModePromptSelection {
    if let selection = promptSelectionsByModeID[modeID] {
      return selection
    }

    return .preset(Self.defaultPromptPresetID)
  }

  func selectPromptPreset(for modeID: String, presetID: String) {
    guard definition(for: modeID) != nil else { return }
    guard Self.defaultPromptPresets.contains(where: { $0.id == presetID }) else { return }
    setPromptSelection(.preset(presetID), for: modeID)
  }

  func saveCustomPrompt(for modeID: String, prompt: String) {
    guard definition(for: modeID) != nil else { return }
    setPromptSelection(.custom(prompt), for: modeID)
  }

  func resetPromptToModeDefault(for modeID: String) {
    guard definition(for: modeID) != nil else { return }
    setPromptSelection(.preset(Self.defaultPromptPresetID), for: modeID)
  }

  func resolvedPromptInstruction(for modeID: String) -> String? {
    guard let mode = definition(for: modeID) else { return nil }
    let modeDefinition = resolvedModeDefinition(for: mode)
    return modeDefinition.llmInstruction
  }

  private func mode(matching input: String) -> ModeDefinition? {
    let normalizedInput = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    
    return modes.first(where: {
      $0.id.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedInput
      || $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedInput
    })
  }
  
  private func persistState() {
    store.save(
      PersistedState(
        selectedModeID: selectedModeID,
        promptSelectionsByModeID: promptSelectionsByModeID
      )
    )
  }

  private func resolvedModeDefinition(for mode: ModeDefinition) -> ModeDefinition {
    var resolvedMode = mode
    resolvedMode.llmInstruction = instruction(for: promptSelection(for: mode.id))
    return resolvedMode
  }

  private func instruction(for promptSelection: ModePromptSelection) -> String? {
    switch promptSelection {
    case let .preset(presetID):
      return Self.defaultPromptPresets.first(where: { $0.id == presetID })?.instruction
    case let .custom(prompt):
      return prompt
    }
  }

  private func setPromptSelection(_ selection: ModePromptSelection, for modeID: String) {
    var updatedSelections = promptSelectionsByModeID
    updatedSelections[modeID] = selection
    promptSelectionsByModeID = updatedSelections
    persistState()
  }

  private static func migratePromptSelections(from legacyModes: [ModeDefinition]) -> [String: ModePromptSelection] {
    var selections: [String: ModePromptSelection] = [:]
    let defaultModesByID = Dictionary(uniqueKeysWithValues: defaultModes.map { ($0.id, $0) })

    for legacyMode in legacyModes {
      guard defaultModesByID[legacyMode.id] != nil else { continue }
      let legacyInstruction = normalizedInstruction(legacyMode.llmInstruction)
      let modeDefaultInstruction = defaultModesByID[legacyMode.id]?.llmInstruction

      if normalizedInstruction(modeDefaultInstruction) == legacyInstruction {
        continue
      }

      if let preset = defaultPromptPresets.first(where: {
        normalizedInstruction($0.instruction) == legacyInstruction
      }) {
        selections[legacyMode.id] = .preset(preset.id)
      } else if let legacyInstruction {
        selections[legacyMode.id] = .custom(legacyInstruction)
      } else {
        selections[legacyMode.id] = .custom("")
      }
    }

    return selections
  }

  private static func normalizedInstruction(_ instruction: String?) -> String? {
    guard let instruction else { return nil }
    let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedInstruction.isEmpty ? "" : trimmedInstruction
  }

  private static let defaultPromptPresetID = "default-default"
  
  static let defaultPromptPresets: [PromptPreset] = [
    PromptPreset(
      id: "raw-default",
      title: "Raw (No Prompt)",
      instruction: nil
    ),
    PromptPreset(
      id: "default-default",
      title: "Default Prompt",
      instruction: "Following is the raw transcription of what the user says. This is what user wants to paste in some application. The dictation result may include some meta comments which are instructions to actually update the text. If you find any, please update the text accordingly. If the user corrects himself because he didn't mean to say something, interpret and remove what is not necessary. But do it with caution. You've got to be sure."
    ),
    PromptPreset(
      id: "email-default",
      title: "Email Prompt",
      instruction: "Following is the raw transcription of what the user said. This is what user wants to paste in an email. The dictation result may include some meta comments which are instructions to actually update the text. If you find any, please update the text accordingly. If the user corrects himself because he didn't mean to say something, interpret and remove what is not necessary. But do it with caution.\n" +
        "You will receive the raw transcription of what the user said. Please rewrite it so that it looks like a professional email."
    ),
    PromptPreset(
      id: "terminal-default",
      title: "Terminal Prompt",
      instruction: "Following is the raw transcription of what the user said. This is what user wants to paste in a terminal, please update the text accordingly. If the user corrects himself because he didn't mean to say something, interpret and remove what is not necessary. But do it with caution.\n" +
        "The user is dictating for a Unix shell terminal. Convert the text into a concise bash/zsh command or command sequence. Return only the command text with no explanations, no markdown, and no surrounding quotes."
    )
  ]

  static let defaultModes: [ModeDefinition] = [
    ModeDefinition(
      id: "raw",
      title: "Raw",
      shortcutStoreKey: AppDefaultsKey.shortcutModeDefaultTrigger,
      defaultShortcut: Shortcut(
        keyCode: KeyCode.from(character: "0")!,
        modifiers: [.control, .option]
      ),
      additionalVocabulary: [],
      llmInstruction: nil
    ),
    ModeDefinition(
      id: "default",
      title: "Default",
      shortcutStoreKey: AppDefaultsKey.shortcutModeDefaultTrigger,
      defaultShortcut: Shortcut(
        keyCode: KeyCode.from(character: "1")!,
        modifiers: [.control, .option]
      ),
      additionalVocabulary: [],
      llmInstruction: "Reformat the user's message. Fix grammar, spelling, and punctuation. Remove filler words like \"um\" and \"uh\". Break long content into paragraphs. Keep the original tone and meaning. Only output the cleaned text, nothing else"
    ),
    ModeDefinition(
      id: "email",
      title: "Email",
      shortcutStoreKey: AppDefaultsKey.shortcutModeEmailTrigger,
      defaultShortcut: Shortcut(
        keyCode: KeyCode.from(character: "2")!,
        modifiers: [.control, .option]
      ),
      additionalVocabulary: [
        "regards",
        "follow-up",
        "ASAP",
        "FYI",
        "best regards"
      ],
      llmInstruction: "Reformat the user's message. Fix grammar, spelling, and punctuation. Remove filler words like \"um\" and \"uh\". Break long content into paragraphs. Keep the original tone and meaning. Only output the cleaned text, nothing else\n" +
        "Only if the message could be an email, format it like one."
    ),
    ModeDefinition(
      id: "terminal",
      title: "Terminal",
      shortcutStoreKey: AppDefaultsKey.shortcutModeTerminalTrigger,
      defaultShortcut: Shortcut(
        keyCode: KeyCode.from(character: "3")!,
        modifiers: [.control, .option]
      ),
      additionalVocabulary: [
        "bash",
        "zsh",
        "grep",
        "awk",
        "sed",
        "chmod",
        "docker",
        "compose",
        "chown",
        "sudo",
        "mkdir",
        "rm -rf",
        "curl",
        "ssh"
      ],
      llmInstruction: "The user's message is an input for a Unix shell terminal. Convert the text into a concise bash/zsh command or command sequence. Return only the command text with no explanations, no markdown, and no surrounding quotes."
    )
  ]
}
