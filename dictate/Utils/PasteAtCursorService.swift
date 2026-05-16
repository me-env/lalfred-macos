import AppKit
import CoreGraphics
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PasteAtCursorService")


struct PasteAtCursorService {
  private let accessibilityPermissionService = AccessibilityPermissionService()
  private let cursorContextReader: CursorContextReading

  init(cursorContextReader: CursorContextReading = CursorContextReader()) {
    self.cursorContextReader = cursorContextReader
  }

  func paste(_ text: String) -> Bool {
    logger.info("[PasteAtCursorService] paste() called. text='\(text)'")

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

    let cursorContext = cursorContextReader.readContext()
    let textToPaste = PasteTextTransformer.transform(text, context: cursorContext)
    if textToPaste != text {
      logger.info("[PasteAtCursorService] Adapted text for cursor context: '\(textToPaste)'")
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let didWritePasteboard = pasteboard.setString(textToPaste, forType: .string)
    logger.info("[PasteAtCursorService] Pasteboard write success: \(didWritePasteboard)")

    guard didWritePasteboard else {
      logger.error("[PasteAtCursorService] Aborting: failed to write pasteboard")
      return false
    }

    guard let source = CGEventSource(stateID: .hidSystemState) else {
      logger.error("[PasteAtCursorService] Aborting: failed to create CGEventSource")
      return false
    }

    guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
          let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false) else {
      logger.error("[PasteAtCursorService] Aborting: failed to create keyboard CGEvents")
      return false
    }

    logger.info("[PasteAtCursorService] Posting Cmd+V events (command on keyDown only)")
    vDown.flags = .maskCommand
    vDown.post(tap: .cghidEventTap)

    vUp.flags = []
    vUp.post(tap: .cghidEventTap)
    
    logger.info("[PasteAtCursorService] Cmd+V events posted")
    return true
  }
}
