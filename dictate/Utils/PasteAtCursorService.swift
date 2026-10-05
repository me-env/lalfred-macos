import AppKit
import CoreGraphics
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PasteAtCursorService")


struct PasteAtCursorService {
  private let accessibilityPermissionService = AccessibilityPermissionService()
  private let cursorContextReader: CursorContextReading
  private let contextPasteHistory: ContextPasteRecording
  private let userDefaults: UserDefaults

  init(
    cursorContextReader: CursorContextReading = CursorContextReader(),
    contextPasteHistory: ContextPasteRecording = ContextPasteHistory(),
    userDefaults: UserDefaults = .standard
  ) {
    self.cursorContextReader = cursorContextReader
    self.contextPasteHistory = contextPasteHistory
    self.userDefaults = userDefaults
  }

  func paste(_ text: String) -> Bool {
    logger.info("[PasteAtCursorService] NON paste() called. text='\(text)'")

    let trusted = accessibilityPermissionService.isTrusted()
    logger.info("[PasteAtCursorService] Accessibility trusted: \(trusted)")

    guard trusted else {
      _ = accessibilityPermissionService.requestPrompt()
      logger.warning("[PasteAtCursorService] Aborting: accessibility permission is not granted")
      logger.info("[PasteAtCursorService] Current bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")
      logger.info("[PasteAtCursorService] Current bundle path: \(Bundle.main.bundlePath)")
      logger.info("[PasteAtCursorService] Current process id: \(ProcessInfo.processInfo.processIdentifier)")
      return false
    }

    let frontmostApp = NSWorkspace.shared.frontmostApplication
    logger.info("[PasteAtCursorService] Frontmost app: \(frontmostApp?.localizedName ?? "unknown") (pid: \(frontmostApp?.processIdentifier ?? -1))")

    var textToPaste = text
    if userDefaults.bool(forKey: AppDefaultsKey.smartPasteFormatting) {
      let report = cursorContextReader.readContext()
      textToPaste = PasteTextTransformer.transform(text, context: report?.context)
      if let report { contextPasteHistory.record(report) }
      if textToPaste != text {
        logger.info("[PasteAtCursorService] Adapted text for cursor context: '\(textToPaste)'")
      }
    }

    let method = TextInsertionMethod.current(in: userDefaults)
    let didInsert = method.insert(textToPaste)
    logger.info("[PasteAtCursorService] Inserted via \(method.rawValue, privacy: .public): \(didInsert)")
    return didInsert
  }
}
