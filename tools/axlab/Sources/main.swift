import AppKit
import ApplicationServices
import Foundation


let usage = """
  axlab: drives real apps to test smart paste (see tools/axlab/README.md).

    axlab list                          targets in targets.json and their status
    axlab run [options] [target|group…] run the paste-context matrix (all targets by default)
        --update-fixtures               copy the captures into dictateTests/PasteContextFixtures
        --include-private               …including targets that run on a real account
        --no-done-page                  don't open the "you can use your Mac again" page at the end
    axlab focused                       what has focus right now
    axlab editables <bundleId>          text fields in an app, to write a target's `field`
    axlab bench [runs]                  time each context-reading method on the focused field
    axlab find-text <bundleId> <text>…  texts in the app's windows containing one of these, to
                                        pick a target's `windowHas` without dumping everything
    axlab dump [out.json]               focused field's attributes + every text in its window
    axlab keys <bundleId> <key|"text">… press keys / type text, only while that app is in front
  """

// Connects to the window server. Without it, asking the system-wide element for the
// focused element fails (-25204) in a command-line process, even with permission.
_ = NSApplication.shared

let paths = Paths(
  home: URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent()  // .build
    .deletingLastPathComponent()
)
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()

do {
  switch command {
  case "list": try list()
  case "run": try run(arguments)
  case "focused": focused()
  case "editables": try editables(arguments.first ?? "")
  case "bench": bench(runs: arguments.first.flatMap(Int.init) ?? 3)
  case "find-text": try findText(in: arguments.first ?? "", matching: Array(arguments.dropFirst()))
  case "dump": try dump(to: arguments.first)
  case "keys": try keys(arguments)
  default: print(usage)
  }
} catch {
  print("✋ \(error)")
  exit(1)
}


// MARK: - Commands

func list() throws {
  let fixtureNames = (try? FileManager.default.contentsOfDirectory(atPath: paths.fixtures.path)) ?? []
  for target in try TargetList.load(from: paths.targetsFile) {
    let fixtures = fixtureNames.filter { $0.hasPrefix("\(target.id)-case") }.count
    let status = target.skip.map { "skip: \($0)" } ?? (fixtures > 0 ? "\(fixtures) fixtures" : "no fixtures yet")
    print(pad(target.group, 10) + pad(target.id, 24) + status)
  }
}

func run(_ arguments: [String]) throws {
  guard AXIsProcessTrusted() else {
    throw Abort("this terminal needs Accessibility permission (System Settings → Privacy & Security → Accessibility)")
  }
  let updateFixtures = arguments.contains("--update-fixtures")
  let includePrivate = arguments.contains("--include-private")
  let names = arguments.filter { !$0.hasPrefix("--") }
  let targets = try TargetList.load(from: paths.targetsFile).selecting(names)
  let runner = try Runner(paths: paths)

  print("Running \(targets.count) targets. Hands off the keyboard and mouse: clicking anywhere stops the run.\n")
  var reports: [TargetReport] = []
  var stopped: Abort?
  for target in targets {
    do {
      let report = try runner.run(target)
      reports.append(report)
      printReport(report)
    } catch let abort as Abort {
      stopped = abort
      print("\(pad(target.id, 22)) ✋ stopped: \(abort)")
      break
    }
  }

  let summary = summarize(reports)
  try summary.write(to: runner.resultsDirectory.appending(path: "summary.md"), atomically: true, encoding: .utf8)
  print("\nCaptures and summary: \(runner.resultsDirectory.path)")
  if !arguments.contains("--no-done-page") {
    try openDonePage(reports, stopped: stopped, total: targets.count, in: runner.resultsDirectory)
  }
  if let stopped { throw stopped }

  if updateFixtures {
    var copied = 0
    for report in reports {
      guard case .ran(let results) = report.outcome, includePrivate || !report.target.isPrivate else { continue }
      for result in results {
        let destination = paths.fixtures.appending(path: result.file.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: result.file, to: destination)
        copied += 1
      }
    }
    print("Copied \(copied) captures to the fixtures. Check `git diff` for anything private before committing.")
  }
}

func printReport(_ report: TargetReport) {
  defer { report.notes.forEach { print("    note: \($0)") } }
  let name = pad(report.target.id, 22)
  let time = String(format: "%5.1fs", report.duration)
  switch report.outcome {
  case .skipped(let reason):
    print("\(name) –      skipped: \(reason)")
  case .failed(let reason):
    print("\(name) ⛔️ \(time) \(reason)")
  case .ran(let results):
    let passed = results.filter(\.passed).count
    let routes = Set(results.map(\.route)).sorted().joined(separator: " | ")
    print("\(name) \(passed == results.count ? "✅" : "❌") \(time) \(passed)/\(results.count)  \(routes)")
    for result in results {
      var notes: [String] = []
      if !result.passed { notes.append("got \(show(result.result)), expected \(show(result.expected))") }
      if result.confirmed == false { notes.append("typed text never showed up in the field") }
      if case .changed(let change) = result.fixture { notes.append(change) }
      guard !notes.isEmpty else { continue }
      print("    case \(result.number): " + notes.joined(separator: "; "))
    }
  }
}

func summarize(_ reports: [TargetReport]) -> String {
  var lines = ["| Target | Result | Route | Changed vs fixture |", "|---|---|---|---|"]
  for report in reports {
    switch report.outcome {
    case .skipped(let reason):
      lines.append("| \(report.target.id) | skipped | \(reason) | |")
    case .failed(let reason):
      lines.append("| \(report.target.id) | ⛔️ \(reason) | | |")
    case .ran(let results):
      let failed = results.filter { !$0.passed }.map { "\($0.number)" }
      let changed = results.filter { if case .changed = $0.fixture { true } else { false } }.map { "\($0.number)" }
      let result = failed.isEmpty ? "✅ \(results.count)/\(results.count)" : "❌ cases \(failed.joined(separator: ", "))"
      let routes = Set(results.map(\.route)).sorted().joined(separator: "<br>")
      lines.append("| \(report.target.id) | \(result) | \(routes) | \(changed.joined(separator: ", ")) |")
    }
  }
  return lines.joined(separator: "\n") + "\n"
}

func focused() {
  guard let element = AXAttr.copyFocusedElement() else { print("nothing has focus"); return }
  var pid: pid_t = 0
  AXUIElementGetPid(element, &pid)
  let app = NSRunningApplication(processIdentifier: pid)
  let state = FieldState.current()
  print("\(app?.localizedName ?? "?") (\(app?.bundleIdentifier ?? "?")): \(describe(element))")
  print("  value: \(state?.value.map { show(String($0.suffix(80))) } ?? "unreadable")")
  print("  range: \(state?.rangeLocation.map(String.init) ?? "-")+\(state?.rangeLength.map(String.init) ?? "-")")
}

func editables(_ bundleId: String) throws {
  guard let app = appElement(bundleId) else { throw Abort("\(bundleId) isn't running") }
  let fields = findElements(in: app) { element in
    let role = AXAttr.string(kAXRoleAttribute, in: element) ?? ""
    return FieldMatch.textRoles.contains(role) || role == "AXWebArea"
  }
  for field in fields {
    let window = AXAttr.UIElement(kAXWindowAttribute, in: field).flatMap { AXAttr.string(kAXTitleAttribute, in: $0) }
    print("\(describe(field))  window='\(window ?? "")'")
  }
}

func bench(runs: Int) {
  guard let element = AXAttr.copyFocusedElement() else { print("nothing has focus"); return }
  func milliseconds(_ block: () -> Void) -> Double {
    var best = Double.infinity
    for _ in 0..<runs {
      let start = CFAbsoluteTimeGetCurrent()
      block()
      best = min(best, (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
    return best
  }
  var facts: CursorElementFacts!
  let factsTime = milliseconds { facts = CursorElementFacts(element: element) }
  let rule = CursorContextRules.rule(for: facts)
  print("rule: \(rule.name)")
  print(String(format: "  %-30@ %7.1f ms", "facts" as NSString, factsTime))
  for method in CursorContextMethod.allCases {
    var reading: CursorReading?
    let time = milliseconds { reading = method.read(element) }
    let role = rule.methods.first == method ? "  ← used" : (rule.methods.contains(method) ? "  ← fallback" : "")
    let length = reading.map { "\($0.textBeforeCursor.count) chars" } ?? "unsupported"
    print(String(format: "  %-30@ %7.1f ms  %@%@", method.displayName as NSString, time, length as NSString, role as NSString))
  }
  let total = milliseconds { _ = CursorContextReader().readContext() }
  print(String(format: "  %-30@ %7.1f ms", "readContext (what pasting does)" as NSString, total))
}

func pad(_ text: String, _ width: Int) -> String {
  text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
}


/// Everything that could tell an editor's mode apart: the focused field's snapshot, plus
/// every text, title and description in its window (status bars, mode indicators).
func dump(to path: String?) throws {
  guard var snapshot = CursorContextProbe().capture(), let element = AXAttr.copyFocusedElement() else {
    throw Abort("nothing has focus")
  }
  snapshot.note = "axlab dump"
  var texts: [String] = []
  if let window = AXAttr.UIElement(kAXWindowAttribute, in: element) {
    for node in findElements(in: window, limit: 5_000, where: { _ in true }) where !CFEqual(node, element) {
      let role = AXAttr.string(kAXRoleAttribute, in: node) ?? "?"
      for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        guard let text = AXAttr.string(attribute, in: node), !text.isEmpty, text.count < 200 else { continue }
        texts.append("\(role) \(attribute): \(text)")
      }
    }
  }
  let state = FieldState.current()
  print("\(describe(element)) range=\(state?.rangeLocation.map(String.init) ?? "-")+\(state?.rangeLength.map(String.init) ?? "-") value=\(state?.value.map { show(String($0.suffix(60))) } ?? "unreadable")")
  print("window texts: \(texts.count)")
  guard let path else { texts.forEach { print("  \($0)") }; return }
  var data = try Runner.encoder.encode(snapshot)
  data.append(contentsOf: Array("\n".utf8))
  data.append(try JSONSerialization.data(withJSONObject: texts, options: .prettyPrinted))
  try data.write(to: URL(fileURLWithPath: path))
}

/// `axlab keys com.apple.dt.Xcode escape i "hello" cmd+a`: a word made only of known key
/// names is pressed, anything quoted with spaces or unknown is typed.
func keys(_ arguments: [String]) throws {
  guard let bundleId = arguments.first else { throw Abort("usage: axlab keys <bundleId> <key|text>…") }
  for argument in arguments.dropFirst() {
    guard frontmostBundleId() == bundleId else { throw Abort("\(bundleId) isn't in front, stopping") }
    if let key = try? KeyCombo(argument) {
      let source = CGEventSource(stateID: .hidSystemState)
      for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: keyDown)
        event?.flags = key.flags
        event?.post(tap: .cghidEventTap)
        usleep(8_000)
      }
    } else {
      for character in argument {
        var units = Array(String(character).utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
          let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
          event?.flags = []
          event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
          event?.post(tap: .cghidEventTap)
        }
        usleep(15_000)
      }
    }
    usleep(150_000)
  }
}


func findText(in bundleId: String, matching needles: [String]) throws {
  guard let app = appElement(bundleId), !needles.isEmpty else { throw Abort("usage: axlab find-text <bundleId> <text>…") }
  var seen = Set<String>()
  for node in findElements(in: app, where: { _ in true }) {
    for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
      guard let text = AXAttr.string(attribute, in: node), text.count < 120,
            needles.contains(where: { text.contains($0) }) else { continue }
      let line = "\(AXAttr.string(kAXRoleAttribute, in: node) ?? "?") \(attribute): \(text)"
      if seen.insert(line).inserted { print(line) }
    }
  }
}
