import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// Line-by-line read using AXTextMarker SPI indexed by line number:
///
///   - `AXLineForTextMarker(cursor)`        → 0-based line index of the cursor
///   - `AXTextMarkerRangeForLine(N)`        → marker range of line N
///   - `AXStringForTextMarkerRange(range)`  → text for a marker range
///   - `AXTextMarkerForIndex(0)`            → element-start marker (lower bound)
///
/// Walks backward from the cursor's line, logging each line's marker availability and
/// raw text. Returns the raw concatenation of those lines (no `\n` separators inserted).
enum TextMarkerLineByIndexStrategy {

  private static let maxIterations = 4096

  static func run(in element: AXUIElement, lookback: Int) -> String? {
    logger.debug("[TextMarkerLineByIndex] === Line-by-line via TextMarker (by index) path ===")

    let params = AXAttr.parameterizedAttributeNames(in: element)
    let hasLineForMarker = params.contains("AXLineForTextMarker")
    let hasRangeForLine = params.contains("AXTextMarkerRangeForLine")
    let hasStringForRange = params.contains("AXStringForTextMarkerRange")
    let hasMarkerForIndex = params.contains("AXTextMarkerForIndex")

    logger.debug(
      """
      [TextMarkerLineByIndex] support: \
      AXLineForTextMarker=\(hasLineForMarker, privacy: .public) \
      AXTextMarkerRangeForLine=\(hasRangeForLine, privacy: .public) \
      AXStringForTextMarkerRange=\(hasStringForRange, privacy: .public) \
      AXTextMarkerForIndex=\(hasMarkerForIndex, privacy: .public)
      """
    )

    guard hasLineForMarker, hasRangeForLine, hasStringForRange,
          let cursorMarker = AXMarker.cursor(in: element)
    else {
      logger.debug("[TextMarkerLineByIndex] cursor marker or required params missing")
      return nil
    }
    guard let cursorLine = AXMarker.lineIndex(of: cursorMarker, in: element) else {
      logger.debug("[TextMarkerLineByIndex] AXLineForTextMarker(cursor)=<n/a>")
      return nil
    }
    logger.debug(
      "[TextMarkerLineByIndex] AXLineForTextMarker(cursor)=\(cursorLine, privacy: .public)"
    )

    let lowerBound: Int
    if hasMarkerForIndex,
       let elementStart = AXMarker.elementStart(in: element),
       let startLine = AXMarker.lineIndex(of: elementStart, in: element) {
      lowerBound = startLine
      logger.debug(
        "[TextMarkerLineByIndex] AXTextMarkerForIndex(0).line=\(startLine, privacy: .public)"
      )
    } else {
      lowerBound = 0
      logger.debug("[TextMarkerLineByIndex] lower-bound line=0 (fallback)")
    }

    var collected: [String] = []
    var collectedLength = 0
    var idx = cursorLine
    var iterations = 0
    while idx >= lowerBound, collectedLength < lookback, iterations < maxIterations {
      iterations += 1
      guard let lineRange = AXMarker.lineRange(forLine: idx, in: element) else {
        logger.debug("[TextMarkerLineByIndex] line[\(idx, privacy: .public)] range=<n/a>")
        break
      }

      let queryRange: AnyObject
      let kind: String
      if idx == cursorLine {
        guard let lineStart = AXMarker.startMarker(of: lineRange),
              let qr = AXMarker.createRange(from: lineStart, to: cursorMarker) else {
          logger.debug("[TextMarkerLineByIndex] line[\(idx, privacy: .public)] cursor sub-range failed")
          break
        }
        queryRange = qr
        kind = "lineStart..cursor"
      } else {
        queryRange = lineRange
        kind = "fullLine"
      }

      if let text = AXMarker.string(forRange: queryRange, in: element) {
        logger.debug(
          """
          [TextMarkerLineByIndex] line[\(idx, privacy: .public)] (\(kind, privacy: .public)) \
          len=\(text.utf16.count, privacy: .public) text=\(text, privacy: .private)
          """
        )
        collected.append(text)
        collectedLength += text.utf16.count
      } else {
        logger.debug("[TextMarkerLineByIndex] line[\(idx, privacy: .public)] string=<n/a>")
        break
      }
      idx -= 1
    }

    guard !collected.isEmpty else { return nil }
    return collected.reversed().joined()
  }
}
