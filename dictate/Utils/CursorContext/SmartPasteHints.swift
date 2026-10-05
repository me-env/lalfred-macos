import Foundation


/// Advice about smart paste for one app or website, found while pasting there and shown in
/// the Text Insertion tab until the user dismisses it or the problem goes away.
nonisolated struct SmartPasteHint: Codable, Hashable, Identifiable {
  enum Kind: String, Codable {
    /// A Monaco editor without screen reader mode: only the character before the cursor
    /// can be read (see ``MonacoEditor``).
    case monacoScreenReaderMode
  }

  let kind: Kind
  /// The app ("Cursor"), or the website and its browser ("vscode.dev (Dia)").
  let place: String

  var id: String { "\(kind.rawValue)|\(place)" }
}


/// The hints found so far and the ones dismissed, kept in user defaults as JSON so the
/// settings view can observe them with `@AppStorage`.
nonisolated enum SmartPasteHints {
  static func note(_ hint: SmartPasteHint, in defaults: UserDefaults) {
    var hints = found(in: defaults)
    guard !hints.contains(hint) else { return }
    hints.append(hint)
    write(hints, to: AppDefaultsKey.smartPasteHints, in: defaults)
  }

  /// The problem went away there (e.g. screen reader mode turned on).
  static func resolve(_ hint: SmartPasteHint, in defaults: UserDefaults) {
    var hints = found(in: defaults)
    guard let index = hints.firstIndex(of: hint) else { return }
    hints.remove(at: index)
    write(hints, to: AppDefaultsKey.smartPasteHints, in: defaults)
  }

  static func dismiss(_ hint: SmartPasteHint, in defaults: UserDefaults) {
    var dismissed = dismissedIDs(in: defaults)
    dismissed.insert(hint.id)
    write(dismissed.sorted(), to: AppDefaultsKey.dismissedSmartPasteHints, in: defaults)
  }

  /// Found and not dismissed, oldest first.
  static func active(found: Data?, dismissed: Data?) -> [SmartPasteHint] {
    let dismissedIDs = Set(decode([String].self, from: dismissed) ?? [])
    return (decode([SmartPasteHint].self, from: found) ?? []).filter { !dismissedIDs.contains($0.id) }
  }

  static func active(in defaults: UserDefaults) -> [SmartPasteHint] {
    active(
      found: defaults.data(forKey: AppDefaultsKey.smartPasteHints),
      dismissed: defaults.data(forKey: AppDefaultsKey.dismissedSmartPasteHints)
    )
  }

  private static func found(in defaults: UserDefaults) -> [SmartPasteHint] {
    decode([SmartPasteHint].self, from: defaults.data(forKey: AppDefaultsKey.smartPasteHints)) ?? []
  }

  private static func dismissedIDs(in defaults: UserDefaults) -> Set<String> {
    Set(decode([String].self, from: defaults.data(forKey: AppDefaultsKey.dismissedSmartPasteHints)) ?? [])
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
    data.flatMap { try? JSONDecoder().decode(type, from: $0) }
  }

  private static func write<T: Encodable>(_ value: T, to key: String, in defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key)
  }
}
