import AppKit
import ApplicationServices
import Foundation


/// The target can't be tested this run (field not found, unexpected content…). The run
/// moves on to the next target, unlike ``Abort`` which stops everything.
struct TargetFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}


struct CaseResult {
  enum FixtureComparison {
    case new
    case same
    case changed(String)
  }

  let number: Int
  let result: String
  let expected: String
  let route: String
  /// Whether the field was seen holding the typed text before reading it. `nil` when the
  /// field doesn't expose its text.
  let confirmed: Bool?
  let fixture: FixtureComparison
  let file: URL

  var passed: Bool { result == expected }
}


struct TargetReport {
  enum Outcome {
    case skipped(String)
    case failed(String)
    case ran([CaseResult])
  }

  let target: Target
  let outcome: Outcome
  let duration: TimeInterval
  var notes: [String] = []
}


struct Paths {
  /// `tools/axlab`.
  let home: URL
  var repo: URL { home.deletingLastPathComponent().deletingLastPathComponent() }
  var targetsFile: URL { home.appending(path: "targets.json") }
  var scratch: URL { home.appending(path: "scratch") }
  var testbed: URL { repo.appending(path: "tools/paste-context-testbed.html") }
  var fixtures: URL { repo.appending(path: "dictateTests/PasteContextFixtures") }
}


final class Runner {
  let paths: Paths
  let resultsDirectory: URL

  init(paths: Paths) throws {
    self.paths = paths
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy-MM-dd_HHmmss"
    resultsDirectory = paths.home.appending(path: "results/\(stamp.string(from: Date()))")
    try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
  }

  func run(_ target: Target) throws -> TargetReport {
    let start = Date()
    var notes: [String] = []
    func report(_ outcome: TargetReport.Outcome) -> TargetReport {
      TargetReport(target: target, outcome: outcome, duration: Date().timeIntervalSince(start), notes: notes)
    }
    if let reason = target.skip { return report(.skipped(reason)) }

    let driver = Driver(target: target)
    let savedClipboard = target.pastesText ? Driver.saveClipboard() : nil
    defer { savedClipboard.map(Driver.restoreClipboard) }
    do {
      guard let field = try reach(target, driver: driver) else {
        let hint = target.setup.map { " Setup: \($0)" } ?? ""
        throw TargetFailure("field not found after opening the app.\(hint)")
      }
      try driver.focus(field)
      if !waitUntil(timeout: 2, { (try? driver.check()) != nil }) {
        do { try driver.check() } catch { throw TargetFailure("couldn't focus the field: \(error)") }
      }
      var results: [CaseResult] = []
      for matrixCase in MatrixCase.cases(multiline: target.isMultiline) {
        results.append(try run(matrixCase, on: target, driver: driver))
      }
      if driver.hasVimMode { notes.append("Vim normal mode: pressed i to switch to insert mode") }
      try clear(target, driver: driver)
      return report(.ran(results))
    } catch let failure as TargetFailure {
      return report(.failed(failure.description))
    }
  }

  // MARK: - Reaching the field

  private func reach(_ target: Target, driver: Driver) throws -> AXUIElement? {
    let opening = target.open
    if opening.shortcutFirst != true, let field = findField(target) {
      try activate(target)
      return field
    }
    try launch(target)

    var shortcutPressed = false
    if let shortcut = opening.shortcut, opening.shortcutFirst == true {
      waitUntil(timeout: 10, every: 0.1) { hasWindow(target) }
      try driver.pressShortcut(shortcut)
      shortcutPressed = true
    }

    let start = Date()
    var field: AXUIElement?
    var shortcutError: Error?
    waitUntil(timeout: 25, every: 0.3) {
      field = findField(target)
      if field == nil, !shortcutPressed, let shortcut = opening.shortcut,
         Date().timeIntervalSince(start) > 2, hasWindow(target) {
        shortcutPressed = true
        do { try driver.pressShortcut(shortcut) } catch { shortcutError = error }
      }
      return field != nil || shortcutError != nil
    }
    if let shortcutError { throw shortcutError }
    return field
  }

  /// The focused element when it's the field, else the first match in the app's tree.
  private func findField(_ target: Target) -> AXUIElement? {
    if let focused = AXAttr.copyFocusedElement(), belongs(focused, to: target), target.field.matchesWithWindow(focused) {
      return focused
    }
    guard let app = appElement(target.app) else { return nil }
    return findElements(in: app) { target.field.matches($0) }.first { target.field.matchesWithWindow($0) }
  }

  private func belongs(_ element: AXUIElement, to target: Target) -> Bool {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == target.app
  }

  private func hasWindow(_ target: Target) -> Bool {
    guard let app = appElement(target.app) else { return false }
    return !(AXAttr.UIElementArray(kAXWindowsAttribute, in: app) ?? []).isEmpty
  }

  private func launch(_ target: Target) throws {
    var arguments = ["-b", target.app]
    if let file = target.open.file {
      arguments.append(try scratchFile(file).path)
    } else if let url = target.open.url {
      arguments.append(url)
    } else if target.open.testbed == true {
      arguments.append(paths.testbed.path)
    }
    try open(arguments)
    guard waitUntil(timeout: 15, every: 0.1, { isFrontmost(target) }) else {
      throw TargetFailure("\(target.app) didn't come to the front. Is it installed?")
    }
  }

  private func activate(_ target: Target) throws {
    guard !isFrontmost(target) else { return }
    try open(["-b", target.app])
    guard waitUntil(timeout: 10, every: 0.05, { isFrontmost(target) }) else {
      throw TargetFailure("\(target.app) didn't come to the front")
    }
  }

  private func isFrontmost(_ target: Target) -> Bool {
    frontmostBundleId() == target.app
  }

  private func open(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TargetFailure("`open \(arguments.joined(separator: " "))` failed")
    }
  }

  /// `scratch/<name>`, created empty when missing.
  private func scratchFile(_ name: String) throws -> URL {
    let url = paths.scratch.appending(path: name)
    guard !FileManager.default.fileExists(atPath: url.path) else { return url }
    try FileManager.default.createDirectory(at: paths.scratch, withIntermediateDirectories: true)
    if url.pathExtension == "docx" {
      let empty = paths.scratch.appending(path: ".empty.txt")
      try Data().write(to: empty)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
      process.arguments = ["-convert", "docx", empty.path, "-output", url.path]
      try process.run()
      process.waitUntilExit()
    } else {
      try Data().write(to: url)
    }
    return url
  }

  // MARK: - Cases

  private func run(_ matrixCase: MatrixCase, on target: Target, driver: Driver) throws -> CaseResult {
    // Before clearing and again after: ⌘A ⌫ can drop a Vim field back to normal mode.
    if try leaveVimNormalMode(target, driver: driver) { driver.hasVimMode = true }
    try clear(target, driver: driver)
    if try leaveVimNormalMode(target, driver: driver) { driver.hasVimMode = true }
    for step in matrixCase.steps {
      switch step {
      case .type(let text):
        try driver.type(text)
      case .newline:
        try driver.type("\n")
      case .left(let count):
        let before = FieldState.current()?.rangeLocation
        if target.pastesText, let before, try driver.moveCursor(to: before - count) { break }
        try driver.press("left", times: count)
        if before != nil { waitUntil(timeout: 0.5) { FieldState.current()?.rangeLocation != before } }
      }
    }

    let typed = FieldState.letters(matrixCase.content)
    var confirmed: Bool?
    if FieldState.current()?.value != nil {
      confirmed = waitUntil(timeout: 1.5) {
        guard let state = FieldState.current() else { return false }
        return typed.isEmpty ? state.isEmpty == true : state.letters == typed
      }
    }
    waitForSettle(quiet: target.settleTime)
    try driver.check()

    guard var snapshot = CursorContextProbe().capture() else { throw Abort("lost the focused element") }
    snapshot.sampleText = MatrixCase.sample
    snapshot.expectedResult = matrixCase.expected
    snapshot.note = "\(target.id) case \(matrixCase.number): \(matrixCase.note)"
    let file = resultsDirectory.appending(path: "\(target.id)-case\(matrixCase.number).json")
    try Self.encoder.encode(snapshot).write(to: file)

    let (result, route) = Self.evaluate(snapshot)
    return CaseResult(
      number: matrixCase.number,
      result: result,
      expected: matrixCase.expected,
      route: route,
      confirmed: confirmed,
      fixture: compareWithFixture(named: file.lastPathComponent, result: result, route: route),
      file: file
    )
  }

  /// Vim mode (Xcode, kindaVim…) turns typed letters into commands. Types "i": a plain
  /// field shows it, and it's deleted again; a Vim field in normal mode shows nothing and is
  /// now in insert mode, where it stays since the harness never presses Escape.
  /// Only works when the field exposes its text.
  private func leaveVimNormalMode(_ target: Target, driver: Driver) throws -> Bool {
    // Pasting and ⌘ shortcuts reach the app whatever Vim's mode: nothing to switch.
    guard !target.pastesText, let before = FieldState.current()?.value else { return false }
    try driver.type("i")
    if waitUntil(timeout: 0.4, { FieldState.current()?.value != before }) {
      try driver.press("delete")
      waitUntil(timeout: 0.4) { FieldState.current()?.value == before }
      return false
    }
    return true
  }

  /// Empties the field with ⌘A ⌫, but only when it holds nothing the harness didn't type,
  /// so a wrongly matched field (a real note, a draft) is never wiped.
  private func clear(_ target: Target, driver: Driver) throws {
    guard let state = FieldState.current() else { throw Abort("nothing has focus") }
    if state.isEmpty == true { return }
    // A field pinned to a window (axlab's scratch file, the chat with yourself) is a scratch
    // field: anything there is ours, including fragments an app mangled (Vim commands).
    if target.field.windowTitle == nil, target.field.windowHas == nil {
      guard let value = state.value else {
        throw TargetFailure("the field doesn't expose its text, and no windowTitle / windowHas proves it's a scratch field")
      }
      guard Self.holdsOnlyMatrixText(value) else {
        throw TargetFailure("the field holds text the harness didn't type, so it won't clear it: \"\(value.prefix(60))\"")
      }
    }

    for _ in 0..<3 {
      try driver.press("cmd+a")
      // ⌫ is a Vim command; cut goes to the app (the clipboard is restored afterwards).
      try driver.press(target.pastesText ? "cmd+x" : "delete")
      if waitUntil(timeout: 1, { FieldState.current()?.isEmpty ?? true }) {
        waitForSettle(quiet: target.settleTime)
        return
      }
    }
    throw TargetFailure("couldn't empty the field (it holds \"\(FieldState.current()?.value?.prefix(60) ?? "?")\")")
  }

  static func holdsOnlyMatrixText(_ value: String) -> Bool {
    value.lowercased()
      .replacingOccurrences(of: "hey|there|done|hello|world", with: "", options: .regularExpression)
      .allSatisfy { !$0.isLetter && !$0.isNumber }
  }

  // MARK: - Evaluation

  static func evaluate(_ snapshot: CursorContextSnapshot) -> (result: String, route: String) {
    let resolution = snapshot.resolution
    let result = PasteTextTransformer.transform(snapshot.sampleText, context: resolution.context)
    let route = "\(resolution.rule.name) → \(resolution.method?.displayName ?? "pasted unchanged")"
    return (result, route)
  }

  private func compareWithFixture(named name: String, result: String, route: String) -> CaseResult.FixtureComparison {
    let url = paths.fixtures.appending(path: name)
    guard let data = try? Data(contentsOf: url),
          let fixture = try? Self.decoder.decode(CursorContextSnapshot.self, from: data) else { return .new }
    let (oldResult, oldRoute) = Self.evaluate(fixture)
    if oldResult == result, oldRoute == route { return .same }
    return .changed("fixture gives \(show(oldResult)) via \(oldRoute)")
  }

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}


/// Quoted, with spaces and line breaks visible.
func show(_ text: String) -> String {
  "\"" + text.replacingOccurrences(of: " ", with: "␣").replacingOccurrences(of: "\n", with: "⏎") + "\""
}
