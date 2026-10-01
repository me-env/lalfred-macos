import AppKit
import Foundation
import Observation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PasteContextInspector")


/// Drives the paste context inspector: polls the focused element of whatever app the user
/// clicks into, and captures a full ``CursorContextSnapshot`` whenever the focus or cursor
/// moves. Focus inside L'Alfred itself is ignored, so the inspector keeps showing the last
/// external field while you interact with it.
@Observable
final class PasteContextInspectorModel {
  var isLive = true
  var sampleText = "Hello world"
  var expectedResult = ""
  var note = ""
  private(set) var snapshot: CursorContextSnapshot?
  private(set) var isAccessibilityTrusted = false
  private(set) var statusMessage: String?

  @ObservationIgnored private let probe = CursorContextProbe()
  @ObservationIgnored private let accessibilityPermissionService = AccessibilityPermissionService()
  @ObservationIgnored private var timer: Timer?
  @ObservationIgnored private var lastFingerprint: CursorContextProbe.Fingerprint?
  @ObservationIgnored private var snapshotElementHash: CFHashCode?

  static let pollInterval: TimeInterval = 0.5

  static var snapshotsDirectory: URL {
    URL.applicationSupportDirectory
      .appending(path: Bundle.main.bundleIdentifier ?? "fr.lalfred.dictate")
      .appending(path: "PasteContextSnapshots")
  }

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    tick()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func requestAccessibility() {
    _ = accessibilityPermissionService.requestPrompt()
  }

  /// Forces a capture even if nothing moved (still skips L'Alfred's own fields).
  func captureNow() {
    lastFingerprint = nil
    refresh(force: true)
  }

  // MARK: - Outputs

  /// What pasting `sampleText` would produce, routed through the rules like pasting is.
  var productionResult: String? {
    guard let snapshot else { return nil }
    return PasteTextTransformer.transform(sampleText, context: snapshot.resolution.context)
  }

  /// What pasting `sampleText` would produce if `method` were used.
  func result(for method: CursorContextMethod) -> String? {
    guard let reading = snapshot?.reading(for: method) else { return nil }
    return PasteTextTransformer.transform(sampleText, context: reading.context)
  }

  /// True when the methods that could read something don't agree on the context.
  var strategiesDisagree: Bool {
    guard let snapshot else { return false }
    let contexts = Set(CursorContextMethod.allCases.compactMap { snapshot.reading(for: $0)?.context })
    return contexts.count > 1
  }

  func copyReport() {
    guard let snapshot = snapshotForExport() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(PasteContextReport.markdown(for: snapshot), forType: .string)
    statusMessage = "Report copied to the clipboard."
  }

  func saveSnapshot() {
    guard let snapshot = snapshotForExport() else { return }
    do {
      let directory = Self.snapshotsDirectory
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appending(path: Self.fileName(for: snapshot))
      try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
      statusMessage = "Saved \(url.lastPathComponent)"
      logger.info("Saved snapshot to \(url.path, privacy: .public)")
    } catch {
      statusMessage = "Save failed: \(error.localizedDescription)"
      logger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
    }
  }

  func revealSnapshotsFolder() {
    let directory = Self.snapshotsDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([directory])
  }

  // MARK: - Polling

  private func tick() {
    isAccessibilityTrusted = accessibilityPermissionService.isTrusted()
    guard isLive else { return }
    refresh(force: false)
  }

  private func refresh(force: Bool) {
    guard isAccessibilityTrusted else { return }
    guard let fingerprint = probe.fingerprint() else { return }
    guard fingerprint.pid != ProcessInfo.processInfo.processIdentifier else { return }
    guard force || fingerprint != lastFingerprint else { return }
    lastFingerprint = fingerprint

    guard let captured = probe.capture() else { return }
    // The expectation describes one field; drop it when focus lands somewhere else,
    // but keep it while the cursor moves within the same field.
    if fingerprint.elementHash != snapshotElementHash {
      expectedResult = ""
      note = ""
    }
    snapshotElementHash = fingerprint.elementHash
    snapshot = captured
    statusMessage = nil
  }

  // MARK: - Export

  private func snapshotForExport() -> CursorContextSnapshot? {
    guard var snapshot else { return nil }
    snapshot.sampleText = sampleText
    snapshot.expectedResult = expectedResult.isEmpty ? nil : expectedResult
    snapshot.note = note.isEmpty ? nil : note
    return snapshot
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static func fileName(for snapshot: CursorContextSnapshot) -> String {
    let app = (snapshot.app.bundleIdentifier ?? snapshot.app.name ?? "unknown")
      .replacingOccurrences(of: "/", with: "-")
    let role = snapshot.element.role ?? "element"
    let stamp = snapshot.capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
      .replacingOccurrences(of: ":", with: "")
    return "\(app)_\(role)_\(stamp).json"
  }
}


/// Human-readable dump of a snapshot, for pasting into an issue or a chat.
enum PasteContextReport {
  static func markdown(for snapshot: CursorContextSnapshot) -> String {
    let resolution = snapshot.resolution
    var lines: [String] = []
    let app = snapshot.app
    lines.append("## \(app.name ?? "Unknown app") (\(app.bundleIdentifier ?? "no bundle id"), pid \(app.pid))")
    lines.append("")
    lines.append("- Element: \(snapshot.element.headline) — \(snapshot.element.roleDescription ?? "")")
    if let identifier = snapshot.element.identifier { lines.append("- Identifier: \(identifier)") }
    if !snapshot.element.domClassList.isEmpty {
      lines.append("- DOM classes: \(snapshot.element.domClassList.joined(separator: " "))")
    }
    if let range = snapshot.element.selectedRange {
      lines.append("- Selected range: location \(range.location), length \(range.length)")
    }
    lines.append("- Rule: \(resolution.rule.name) → \(resolution.method?.displayName ?? "paste unchanged")")
    lines.append("- Sample text: \(snapshot.sampleText.debugDescription)")
    if let expected = snapshot.expectedResult { lines.append("- Expected result: \(expected.debugDescription)") }
    if let note = snapshot.note { lines.append("- Note: \(note)") }

    lines.append("")
    lines.append("### Methods")
    for method in CursorContextMethod.allCases {
      lines.append("")
      lines.append("**\(method.displayName)**\(method == resolution.method ? " (used when pasting)" : "")")
      guard let reading = snapshot.reading(for: method) else {
        lines.append("unsupported")
        continue
      }
      let context = reading.context
      lines.append("```")
      lines.append(reading.textBeforeCursor.suffix(200) + "<CURSOR>" + (reading.textAfterCursor ?? "").prefix(60))
      lines.append("```")
      lines.append(
        "prev=\(context.previousCharacter.map { String($0) }.debugDescription) " +
        "prevNonWS=\(context.previousNonWhitespaceCharacter.map { String($0) }.debugDescription) " +
        "lineBreak=\(context.hasLineBreakBeforeCursor)"
      )
    }

    lines.append("")
    lines.append("### Attributes")
    for attribute in snapshot.attributes {
      lines.append("- \(attribute.name): \(attribute.value)")
    }
    lines.append("")
    lines.append("Parameterized: \(snapshot.parameterizedAttributes.joined(separator: ", "))")
    lines.append("Actions: \(snapshot.actions.joined(separator: ", "))")

    lines.append("")
    lines.append("### Ancestors")
    for (depth, ancestor) in snapshot.ancestors.enumerated() {
      let classes = ancestor.domClassList.isEmpty ? "" : " .\(ancestor.domClassList.joined(separator: "."))"
      lines.append("\(String(repeating: "  ", count: depth))- \(ancestor.headline)\(classes)")
    }
    return lines.joined(separator: "\n")
  }
}
