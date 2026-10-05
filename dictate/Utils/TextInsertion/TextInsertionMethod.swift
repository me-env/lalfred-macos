import AppKit
import ApplicationServices
import CoreGraphics
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "TextInsertion")


/// How the dictated text gets into the focused field. Picked by the user in
/// Settings → Text Insertion; the same method is used in every app.
///
/// Adding a method: add a case, its `title` + `explanation`, and a line in `insert`.
enum TextInsertionMethod: String, CaseIterable, Identifiable {
  case paste
  case pasteRestoringClipboard
  case typeKeystrokes
  case accessibilityInsert

  static let `default` = TextInsertionMethod.paste

  var id: String { rawValue }

  var title: String {
    switch self {
    case .paste: "Paste (⌘V)"
    case .pasteRestoringClipboard: "Paste, then restore clipboard"
    case .typeKeystrokes: "Type as keystrokes"
    case .accessibilityInsert: "Insert via Accessibility"
    }
  }

  var explanation: String {
    switch self {
    case .paste:
      "Puts the text on the clipboard and presses ⌘V. Fast and works almost everywhere, but replaces what you had copied."
    case .pasteRestoringClipboard:
      "Same as Paste, then puts your previous clipboard back about a second later, unless you copied something new meanwhile."
    case .typeKeystrokes:
      "Types the text without touching the clipboard. Slower, and apps react to each key: autocorrect, completion, auto-indent. New lines are typed as ⇧↩ so chat apps don't send."
    case .accessibilityInsert:
      "Replaces the selection in the focused field directly, without clipboard or keystrokes. Falls back to Paste when the field doesn't take it. Untested outside native fields."
    }
  }

  /// Inserts `text` at the cursor of the focused field.
  func insert(_ text: String) -> Bool {
    switch self {
    case .paste: Self.paste(text)
    case .pasteRestoringClipboard: Self.pasteRestoringClipboard(text)
    case .typeKeystrokes: Self.type(text)
    case .accessibilityInsert: Self.insertViaAccessibility(text) || Self.paste(text)
    }
  }

  static func current(in defaults: UserDefaults) -> TextInsertionMethod {
    defaults.string(forKey: AppDefaultsKey.textInsertionMethod)
      .flatMap(TextInsertionMethod.init(rawValue:)) ?? .default
  }

  // MARK: - Paste

  private static func paste(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      logger.error("Failed to write pasteboard")
      return false
    }
    return pressCommandV()
  }

  /// How long the target app gets to read the pasteboard before it's restored. Apps read
  /// it asynchronously after ⌘V, Electron ones sometimes noticeably late.
  private static let clipboardRestoreDelay: TimeInterval = 1.0

  private static func pasteRestoringClipboard(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    let saved = copyItems(of: pasteboard)
    guard paste(text) else { return false }

    let changeCountAfterPaste = pasteboard.changeCount
    DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
      // Something new was copied meanwhile: keep it.
      guard pasteboard.changeCount == changeCountAfterPaste else { return }
      pasteboard.clearContents()
      if !saved.isEmpty { pasteboard.writeObjects(saved) }
      logger.info("Restored clipboard (\(saved.count) items)")
    }
    return true
  }

  /// Deep copy of the pasteboard's items: the originals become invalid once it's cleared.
  /// Lazily promised data (e.g. file promises) can't be copied and is lost.
  private static func copyItems(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
  }

  private static func pressCommandV() -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
          let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false) else {
      logger.error("Failed to create ⌘V events")
      return false
    }
    vDown.flags = .maskCommand
    vDown.post(tap: .cghidEventTap)
    // Cmd stays held on key-up, as on real hardware. Clearing it made Raycast
    // resolve a different shortcut.
    vUp.flags = .maskCommand
    vUp.post(tap: .cghidEventTap)
    return true
  }

  // MARK: - Keystrokes

  /// One event carries at most this many UTF-16 units (CGEvent's documented limit is 20).
  static let maxUnitsPerEvent = 20
  private static let delayBetweenEvents: useconds_t = 8_000

  private static func type(_ text: String) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    for chunk in keystrokeChunks(of: text) {
      if chunk == "\n" {
        postKey(36, flags: .maskShift, source: source)  // ⇧↩: a new line, not "send".
      } else {
        postUnicode(chunk, source: source)
      }
      usleep(delayBetweenEvents)
    }
    return true
  }

  /// Splits `text` into runs of at most `maxUnitsPerEvent` UTF-16 units, without cutting a
  /// character in half, and with each line break as its own "\n" chunk.
  static func keystrokeChunks(of text: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    for character in text {
      if character.isNewline {
        if !current.isEmpty { chunks.append(current); current = "" }
        chunks.append("\n")
      } else if current.utf16.count + character.utf16.count > maxUnitsPerEvent {
        chunks.append(current)
        current = String(character)
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }

  private static func postUnicode(_ text: String, source: CGEventSource) {
    var units = Array(text.utf16)
    for keyDown in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
      // Explicitly no modifiers: the dictation shortcut may still be held.
      event.flags = []
      event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
      event.post(tap: .cghidEventTap)
    }
  }

  private static func postKey(_ code: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
    for keyDown in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { continue }
      event.flags = flags
      event.post(tap: .cghidEventTap)
    }
  }

  // MARK: - Accessibility

  /// Sets `AXSelectedText`, which replaces the selection (or inserts at the cursor).
  /// Some fields accept the call without changing anything, so success is only trusted
  /// when `AXValue` changed (or can't be read at all). Chromium updates its AX tree
  /// asynchronously, so the value is polled briefly before falling back, which would
  /// otherwise insert the text twice.
  private static func insertViaAccessibility(_ text: String) -> Bool {
    guard let element = AXAttr.copyFocusedElement() else { return false }
    let before = AXAttr.string(kAXValueAttribute, in: element)
    let error = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
    guard error == .success else {
      logger.info("AXSelectedText not settable (\(error.rawValue)), falling back to paste")
      return false
    }
    guard before != nil else { return true }
    for _ in 0..<valueChangePolls {
      if AXAttr.string(kAXValueAttribute, in: element) != before { return true }
      usleep(valueChangePollInterval)
    }
    logger.info("AXSelectedText accepted but value unchanged, falling back to paste")
    return false
  }

  private static let valueChangePolls = 5
  private static let valueChangePollInterval: useconds_t = 20_000
}

