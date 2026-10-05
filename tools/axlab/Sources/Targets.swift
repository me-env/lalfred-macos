import ApplicationServices
import Foundation


/// One field the harness drives, as listed in `targets.json`.
struct Target: Decodable {
  /// Also the fixture prefix: snapshots are saved as `<id>-case<N>.json`.
  let id: String
  let group: String
  /// Bundle identifier.
  let app: String
  let open: Opening
  let field: FieldMatch
  private let multiline: Bool?
  /// Key that makes a new line, e.g. `shift+return` in chat boxes where ↩ sends.
  private let newline: String?
  /// ↩ sends a message here. Plain ↩ is then refused, whatever `newline` says.
  private let sends: Bool?
  /// Runs on a real account: snapshots may hold private text from around the field, so
  /// they're only copied to the fixtures with `--include-private`.
  private let `private`: Bool?
  /// How long the field must stay unchanged before it's read. Raise it for apps that
  /// update their accessibility tree late.
  private let settleMs: Int?
  /// When focus moves to a popup of the same app (autocomplete), press Escape once to
  /// close it instead of stopping.
  private let escapePopups: Bool?
  /// Put the cases' text in with ⌘V instead of typing it: typed keys trigger autocomplete
  /// (Cursor's editor) or Vim commands. The clipboard is restored after the target.
  private let pasteText: Bool?
  /// Manual steps the harness can't do, printed when the field can't be reached.
  let setup: String?
  /// Listed but not run, with the reason.
  let skip: String?

  var isMultiline: Bool { multiline ?? true }
  var sendsOnReturn: Bool { sends ?? false }
  var isPrivate: Bool { `private` ?? false }
  var settleTime: TimeInterval { Double(settleMs ?? 80) / 1000 }
  var newlineKey: String { newline ?? "return" }
  var escapesPopups: Bool { escapePopups ?? false }
  var pastesText: Bool { pasteText ?? false }
}


struct Opening: Decodable {
  /// File in `tools/axlab/scratch/`, created empty when missing (`.docx` included).
  var file: String?
  var url: String?
  /// Opens `tools/paste-context-testbed.html`.
  var testbed: Bool?
  /// Pressed in the app when the field isn't there after opening, e.g. `cmd+l`.
  var shortcut: String?
  /// Press `shortcut` every time instead (e.g. `cmd+n` for a fresh note), so the harness
  /// never lands in an existing document.
  var shortcutFirst: Bool?
}


/// Which element is the field. Every given criterion must match. It's also the safety
/// check before each keystroke: focus must still be on a matching element.
struct FieldMatch: Decodable {
  /// Defaults to any text field role (AXTextArea, AXTextField, AXComboBox).
  var role: String?
  var domId: String?
  var domClass: String?
  /// `AXDescription`, i.e. the aria-label on the web.
  var description: String?
  /// The field's window title must contain this.
  var windowTitle: String?
  /// `AXIdentifier`, set by native apps (`ChatBar_ComposerTextView`).
  var identifier: String?
  /// `AXRoleDescription`, e.g. Notion's "page title".
  var roleDescription: String?
  /// An element that must be in the field's window, e.g. the header of the chat with
  /// yourself, when nothing on the field tells chats apart. Checked when looking for the
  /// field, not before each key (it walks the whole window).
  var windowHas: WindowElement?

  /// The closest ancestor with this DOM class must contain `text` somewhere: for apps that
  /// keep several pages in one window (Notion tabs), "inside the page titled X".
  var within: Ancestor?

  struct Ancestor: Decodable {
    var domClass: String
    var text: String
  }

  struct WindowElement: Decodable {
    var role: String?
    var identifier: String?
    /// Contained in its value, title or description.
    var text: String?
  }

  static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]

  func matches(_ element: AXUIElement) -> Bool {
    let elementRole = AXAttr.string(kAXRoleAttribute, in: element) ?? ""
    if let role { guard elementRole == role else { return false } }
    else { guard Self.textRoles.contains(elementRole) else { return false } }
    if let domId, AXAttr.string("AXDOMIdentifier", in: element) != domId { return false }
    if let domClass, !(AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? []).contains(domClass) {
      return false
    }
    if let description, AXAttr.string(kAXDescriptionAttribute, in: element) != description { return false }
    if let identifier, AXAttr.string(kAXIdentifierAttribute, in: element) != identifier { return false }
    if let roleDescription, AXAttr.string(kAXRoleDescriptionAttribute, in: element) != roleDescription {
      return false
    }
    if let windowTitle {
      let window = AXAttr.UIElement(kAXWindowAttribute, in: element)
      let title = window.flatMap { AXAttr.string(kAXTitleAttribute, in: $0) } ?? ""
      guard title.contains(windowTitle) else { return false }
    }
    return true
  }

  /// `matches`, plus the checks that walk the tree: `within`, `windowHas`, and a size on
  /// screen (hidden tabs keep zero-sized fields).
  func matchesWithWindow(_ element: AXUIElement) -> Bool {
    guard matches(element), let rect = frame(of: element), rect.width > 0, rect.height > 0 else { return false }
    if let within, !isWithin(element, within) { return false }
    guard let windowHas else { return true }
    guard let window = AXAttr.UIElement(kAXWindowAttribute, in: element) else { return false }
    return !findElements(in: window, limit: 5_000, where: { node in
      if let role = windowHas.role, AXAttr.string(kAXRoleAttribute, in: node) != role { return false }
      if let identifier = windowHas.identifier, AXAttr.string(kAXIdentifierAttribute, in: node) != identifier {
        return false
      }
      guard let text = windowHas.text else { return true }
      return [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].contains {
        AXAttr.string($0, in: node)?.contains(text) == true
      }
    }).isEmpty
  }

  private func isWithin(_ element: AXUIElement, _ ancestor: Ancestor) -> Bool {
    var node = AXAttr.getParent(in: element)
    for _ in 0..<40 {
      guard let current = node else { return false }
      if (AXAttr.stringArray(kAXDOMClassListAttribute, in: current) ?? []).contains(ancestor.domClass) {
        return !findElements(in: current, limit: 3_000, where: { candidate in
          [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].contains {
            AXAttr.string($0, in: candidate)?.contains(ancestor.text) == true
          }
        }).isEmpty
      }
      node = AXAttr.getParent(in: current)
    }
    return false
  }
}


enum TargetList {
  /// `targets.json`, with `targets.local.json` (git-ignored) laid over it: a local entry
  /// replaces the keys it sets in the entry with the same `id` (`"skip": null` un-skips it),
  /// or adds a target. Personal links, names and numbers belong there.
  static func load(from url: URL) throws -> [Target] {
    var entries = try readEntries(url)
    let local = url.deletingLastPathComponent().appending(path: "targets.local.json")
    if FileManager.default.fileExists(atPath: local.path) {
      for override in try readEntries(local) {
        if let index = entries.firstIndex(where: { $0["id"] as? String == override["id"] as? String }) {
          entries[index].merge(override) { _, new in new }
        } else {
          entries.append(override)
        }
      }
    }
    let cleaned = entries.map { $0.filter { !($0.value is NSNull) } }
    return try JSONDecoder().decode([Target].self, from: JSONSerialization.data(withJSONObject: cleaned))
  }

  private static func readEntries(_ url: URL) throws -> [[String: Any]] {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    guard let targets = json?["targets"] as? [[String: Any]] else { throw Abort("\(url.lastPathComponent) has no `targets` list") }
    return targets
  }
}


extension Array where Element == Target {
  /// Targets whose id or group is in `names`; all of them when `names` is empty.
  func selecting(_ names: [String]) throws -> [Target] {
    guard !names.isEmpty else { return self }
    let unknown = names.filter { name in !contains { $0.id == name || $0.group == name } }
    guard unknown.isEmpty else {
      throw Abort("unknown target or group: \(unknown.joined(separator: ", ")). See `axlab list`.")
    }
    return filter { names.contains($0.id) || names.contains($0.group) }
  }
}
