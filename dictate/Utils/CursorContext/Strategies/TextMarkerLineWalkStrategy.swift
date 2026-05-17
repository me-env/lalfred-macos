import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// Line-by-line read using sequential AXTextMarker traversal (no line indices):
///
///   - `AXLineTextMarkerRangeForTextMarker(marker)`         → current line's range
///   - `AXPreviousLineStartTextMarkerForTextMarker(marker)` → previous line's start
///   - `AXStringForTextMarkerRange(range)`                  → text for a range
///
/// Useful for elements where stable line numbering isn't exposed (virtual scrollers).
/// Logs each step of the traversal and returns the raw concatenation of the visited
/// lines (no `\n` separators inserted).
enum TextMarkerLineWalkStrategy {

  private static let maxIterations = 4096

  static func run(in element: AXUIElement, lookback: Int) -> String? {
    logger.debug("[TextMarkerLineWalk] === Line-by-line via TextMarker (sequential walk) path ===")

    let params = AXAttr.parameterizedAttributeNames(in: element)
    let hasLineRangeForMarker = params.contains("AXLineTextMarkerRangeForTextMarker")
    let hasPrevLineStart = params.contains("AXPreviousLineStartTextMarkerForTextMarker")
    let hasStringForRange = params.contains("AXStringForTextMarkerRange")

    logger.debug(
      """
      [TextMarkerLineWalk] support: \
      AXLineTextMarkerRangeForTextMarker=\(hasLineRangeForMarker, privacy: .public) \
      AXPreviousLineStartTextMarkerForTextMarker=\(hasPrevLineStart, privacy: .public) \
      AXStringForTextMarkerRange=\(hasStringForRange, privacy: .public)
      """
    )

    guard hasLineRangeForMarker, hasPrevLineStart, hasStringForRange,
          let cursorMarker = AXMarker.cursor(in: element)
    else {
      logger.debug("[TextMarkerLineWalk] cursor marker or required params missing")
      return nil
    }
    guard let currentLineRange = AXMarker.lineRange(for: cursorMarker, in: element) else {
      logger.debug("[TextMarkerLineWalk] AXLineTextMarkerRangeForTextMarker(cursor)=<n/a>")
      return nil
    }
    guard var lineStart = AXMarker.startMarker(of: currentLineRange) else {
      logger.debug("[TextMarkerLineWalk] startMarker(currentLineRange)=<n/a>")
      return nil
    }

    var collected: [String] = []
    var collectedLength = 0

    if let cursorLineRange = AXMarker.createRange(from: lineStart, to: cursorMarker),
       let text = AXMarker.string(forRange: cursorLineRange, in: element) {
      logger.debug(
        """
        [TextMarkerLineWalk] cursor-line (lineStart..cursor) \
        len=\(text.utf16.count, privacy: .public) text=\(text, privacy: .private)
        """
      )
      collected.append(text)
      collectedLength += text.utf16.count
    } else {
      logger.debug("[TextMarkerLineWalk] cursor-line range/string=<n/a>")
    }

    var step = 0
    while collectedLength < lookback, step < maxIterations {
      step += 1
      guard let prevLineStart = AXMarker.previousLineStart(for: lineStart, in: element) else {
        logger.debug(
          "[TextMarkerLineWalk] step[\(step, privacy: .public)] previousLineStart=<n/a>"
        )
        break
      }
      guard let prevRange = AXMarker.lineRange(for: prevLineStart, in: element) else {
        logger.debug(
          "[TextMarkerLineWalk] step[\(step, privacy: .public)] lineRange(prev)=<n/a>"
        )
        break
      }
      guard let text = AXMarker.string(forRange: prevRange, in: element) else {
        logger.debug(
          "[TextMarkerLineWalk] step[\(step, privacy: .public)] string(prev)=<n/a>"
        )
        break
      }
      logger.debug(
        """
        [TextMarkerLineWalk] step[\(step, privacy: .public)] (fullLine) \
        len=\(text.utf16.count, privacy: .public) text=\(text, privacy: .private)
        """
      )
      collected.append(text)
      collectedLength += text.utf16.count
      lineStart = prevLineStart
    }

    guard !collected.isEmpty else { return nil }
    return collected.reversed().joined()
  }
}
