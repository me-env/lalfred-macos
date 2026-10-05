import AppKit
import ApplicationServices
import Foundation


struct Abort: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}


/// Sends keystrokes and clicks to one target. Each batch of keys is preceded by `check()`:
/// the target app must be frontmost and focus must be on its field. If you click elsewhere
/// or a dialog pops up, the run stops before anything is typed in the wrong place.
final class Driver {
  let target: Target
  /// Set once the field turned out to have a Vim mode: Escape then leaves insert mode, so
  /// closing a popup has to be followed by `i`.
  var hasVimMode = false

  init(target: Target) {
    self.target = target
  }

  func checkFrontmost() throws {
    var front = frontmostBundleId()
    // No answer at all happens briefly while an app launches: give it a moment.
    if front == nil { waitUntil(timeout: 1, every: 0.05) { front = frontmostBundleId(); return front != nil } }
    guard front == target.app else {
      throw Abort("frontmost app is \(front ?? "none"), expected \(target.app)")
    }
  }

  func check() throws {
    try checkFrontmost()
    guard let element = AXAttr.copyFocusedElement() else { throw Abort("nothing has focus in \(target.app)") }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == target.app else {
      throw Abort("focus is in another process (pid \(pid))")
    }
    guard target.field.matches(element) else {
      if target.escapesPopups, escapePopup() { return }
      throw Abort("focus moved off the field, to \(describe(element))")
    }
  }

  /// Escape, then whether focus came back to the field.
  private func escapePopup() -> Bool {
    post(KeyCombo.escape)
    let back = waitUntil(timeout: 1.5) {
      AXAttr.copyFocusedElement().map(self.target.field.matches) ?? false
    }
    if !back { print("    escape didn't bring focus back: \(AXAttr.copyFocusedElement().map(describe) ?? "nothing")") }
    if back, hasVimMode { postUnicode("i") }
    return back
  }

  // MARK: - Keyboard

  func type(_ text: String) throws {
    if target.pastesText { return try paste(text) }
    for chunk in TextInsertionMethod.keystrokeChunks(of: text) {
      try check()
      if chunk == "\n" { try press(target.newlineKey) } else { postUnicode(chunk) }
      usleep(5_000)
    }
  }

  func press(_ combo: String, times: Int = 1) throws {
    let key = try KeyCombo(combo)
    if target.sendsOnReturn, key.code == KeyCombo.returnKey, key.flags.isEmpty {
      throw Abort("refusing to press ↩ in \(target.id): it sends messages")
    }
    for _ in 0..<times {
      try check()
      post(key)
    }
  }

  /// App-level shortcut (e.g. ⌘L to open a chat): only needs the app to be frontmost.
  func pressShortcut(_ combo: String) throws {
    try checkFrontmost()
    post(try KeyCombo(combo))
  }

  private func post(_ key: KeyCombo) {
    let source = CGEventSource(stateID: .hidSystemState)
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: keyDown)
      event?.flags = key.flags
      event?.post(tap: .cghidEventTap)
      usleep(8_000)
    }
  }

  private func postUnicode(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)
    var units = Array(text.utf16)
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
      event?.flags = []
      event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
      event?.post(tap: .cghidEventTap)
    }
  }

  /// Puts the cursor at `location` by setting the field's selected range, which arrow keys
  /// can't do reliably in a Vim mode (visual mode extends a selection instead). Returns
  /// whether the field took it.
  func moveCursor(to location: Int) throws -> Bool {
    try check()
    guard let element = AXAttr.copyFocusedElement() else { return false }
    var range = CFRange(location: max(location, 0), length: 0)
    guard let value = AXValueCreate(.cfRange, &range),
          AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    else { return false }
    return waitUntil(timeout: 0.5) {
      let state = FieldState.current()
      return state?.rangeLocation == range.location && state?.rangeLength == 0
    }
  }

  private func paste(_ text: String) throws {
    try check()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    post(try KeyCombo("cmd+v"))
  }

  /// Deep copy of the clipboard, to put back with `restoreClipboard` once the target is done.
  static func saveClipboard() -> [NSPasteboardItem] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
  }

  static func restoreClipboard(_ items: [NSPasteboardItem]) {
    NSPasteboard.general.clearContents()
    if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
  }

  // MARK: - Mouse

  /// Focuses `element` through accessibility, then clicks it to place the caret.
  func focus(_ element: AXUIElement) throws {
    try checkFrontmost()
    // The field's window may be behind another one of the app (Outlook's compose window
    // behind the main window): raise it, or the click lands on the window in front.
    if let window = AXAttr.UIElement(kAXWindowAttribute, in: element) {
      AXUIElementPerformAction(window, kAXRaiseAction as CFString)
      AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
    usleep(100_000)
    guard let rect = frame(of: element), rect.width > 0, rect.height > 0 else {
      throw Abort("\(target.id): the field has no frame on screen")
    }
    try checkFrontmost()
    let point = CGPoint(x: rect.midX, y: rect.minY + min(rect.height / 2, 20))
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
      CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
      usleep(10_000)
    }
  }
}


struct KeyCombo {
  static let returnKey: CGKeyCode = 36
  static let escape = KeyCombo(code: 53, flags: [])
  private static let codes: [String: CGKeyCode] = [
    "return": 36, "delete": 51, "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "a": 0, "i": 34, "l": 37, "n": 45, "v": 9, "x": 7, "z": 6,
  ]

  let code: CGKeyCode
  let flags: CGEventFlags

  init(code: CGKeyCode, flags: CGEventFlags) {
    self.code = code
    self.flags = flags
  }

  /// `"cmd+shift+a"`, `"left"`, `"shift+return"`.
  init(_ spec: String) throws {
    var parts = spec.lowercased().split(separator: "+").map(String.init)
    guard let name = parts.popLast(), let code = Self.codes[name] else { throw Abort("unknown key '\(spec)'") }
    var flags: CGEventFlags = []
    for modifier in parts {
      switch modifier {
      case "cmd": flags.insert(.maskCommand)
      case "shift": flags.insert(.maskShift)
      case "opt": flags.insert(.maskAlternate)
      case "ctrl": flags.insert(.maskControl)
      default: throw Abort("unknown modifier '\(modifier)' in '\(spec)'")
      }
    }
    self.code = code
    self.flags = flags
  }
}


// MARK: - Accessibility helpers

/// Asked through accessibility: `NSWorkspace.frontmostApplication` only updates while the
/// run loop spins, so it goes stale in this command-line process.
func frontmostBundleId() -> String? {
  var appRef: CFTypeRef?
  guard AXUIElementCopyAttributeValue(
    AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &appRef
  ) == .success, let appRef else { return nil }
  var pid: pid_t = 0
  AXUIElementGetPid(appRef as! AXUIElement, &pid)
  return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
}

func frame(of element: AXUIElement) -> CGRect? {
  var positionRef: CFTypeRef?
  var sizeRef: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
  else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
  AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
  return CGRect(origin: point, size: size)
}

func appElement(_ bundleId: String) -> AXUIElement? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    .map { AXUIElementCreateApplication($0.processIdentifier) }
}

/// Breadth-first search of `root`'s subtree.
func findElements(in root: AXUIElement, limit: Int = 20_000, where match: (AXUIElement) -> Bool) -> [AXUIElement] {
  var queue = [root]
  var index = 0
  var found: [AXUIElement] = []
  while index < queue.count, index < limit {
    let element = queue[index]
    index += 1
    if match(element) { found.append(element) }
    queue.append(contentsOf: AXAttr.getChildren(in: element) ?? [])
  }
  return found
}

func describe(_ element: AXUIElement) -> String {
  var parts = [AXAttr.string(kAXRoleAttribute, in: element) ?? "?"]
  if let id = AXAttr.string("AXDOMIdentifier", in: element), !id.isEmpty { parts.append("#\(id)") }
  let classes = AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? []
  if !classes.isEmpty { parts.append("." + classes.joined(separator: ".")) }
  if let description = AXAttr.string(kAXDescriptionAttribute, in: element), !description.isEmpty {
    parts.append("'\(description)'")
  }
  return parts.joined(separator: " ")
}


// MARK: - Waiting

/// Polls `condition` until it holds or `timeout` runs out. Returns whether it held.
@discardableResult
func waitUntil(timeout: TimeInterval, every interval: TimeInterval = 0.01, _ condition: () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return true }
    usleep(useconds_t(interval * 1_000_000))
  }
  return condition()
}


/// What the focused field shows: compared between polls to know when it stopped changing.
struct FieldState: Equatable {
  var value: String?
  var rangeLocation: Int?
  var rangeLength: Int?
  var characterCount: Int?
  var domClasses: [String] = []
  var childDOMClasses: [String] = []

  static func current() -> FieldState? {
    guard let element = AXAttr.copyFocusedElement() else { return nil }
    let range = AXAttr.selectedRange(in: element)
    // A web area's value is always empty (Mail's compose body): its text is unknown.
    let isWebArea = AXAttr.string(kAXRoleAttribute, in: element) == "AXWebArea"
    return FieldState(
      value: isWebArea ? nil : AXAttr.string(kAXValueAttribute, in: element),
      rangeLocation: range?.location,
      rangeLength: range?.length,
      characterCount: AXAttr.int(kAXNumberOfCharactersAttribute, in: element),
      domClasses: AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? [],
      childDOMClasses: (AXAttr.getChildren(in: element) ?? []).prefix(3).flatMap {
        AXAttr.stringArray(kAXDOMClassListAttribute, in: $0) ?? []
      }
    )
  }

  /// The text's letters, lowercased, without whitespace or invisible characters: enough to
  /// tell what was typed, whatever the app does with line breaks and capitals.
  var letters: String? { value.map(Self.letters) }

  static func letters(_ text: String) -> String {
    text.lowercased().filter { !$0.isWhitespace && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
  }

  /// `nil` when the field doesn't expose its text.
  var isEmpty: Bool? {
    // Chromium exposes an empty editor's placeholder as its value: Quill marks itself
    // `ql-blank`, Tiptap its empty paragraph `is-editor-empty`.
    if domClasses.contains("ql-blank") || childDOMClasses.contains("is-editor-empty") { return true }
    if let letters { return letters.isEmpty }
    return characterCount.map { $0 == 0 }
  }
}


/// Waits until the focused field hasn't changed for `quiet` seconds.
func waitForSettle(quiet: TimeInterval, timeout: TimeInterval = 2) {
  let deadline = Date().addingTimeInterval(timeout)
  var last = FieldState.current()
  var unchangedSince = Date()
  while Date() < deadline {
    usleep(10_000)
    let state = FieldState.current()
    if state != last {
      last = state
      unchangedSince = Date()
    } else if Date().timeIntervalSince(unchangedSince) >= quiet {
      return
    }
  }
}
