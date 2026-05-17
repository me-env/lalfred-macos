import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// Line-by-line read using public CFRange APIs:
///
///   - `AXLineForIndex(cursorPos)`      → 0-based line index of the cursor
///   - `AXRangeForLine(N)`              → CFRange of line N
///   - `kAXStringForRangeParameterizedAttribute(range)` → text for a CFRange
///
/// Walks backward from the cursor's line, logging each line's CFRange and raw text.
/// Returns the raw concatenation of those lines (no `\n` separators inserted) — this
/// is for debugging, line-break preservation is intentionally out of scope here.
enum CFRangeLineByLineStrategy {

  private static let maxIterations = 4096

  static func run(in element: AXUIElement, cursorPos: Int?, lookback: Int) -> String? {
    logger.debug("[CFRangeLines] === Line-by-line via CFRange path ===")

    let params = AXAttr.parameterizedAttributeNames(in: element)
    let hasLineForIndex = params.contains("AXLineForIndex")
    let hasRangeForLine = params.contains("AXRangeForLine")

    logger.debug(
      """
      [CFRangeLines] support: \
      AXLineForIndex=\(hasLineForIndex, privacy: .public) \
      AXRangeForLine=\(hasRangeForLine, privacy: .public) \
      cursorPos=\(describe(cursorPos), privacy: .public)
      """
    )

    guard let cursorPos, hasLineForIndex, hasRangeForLine else { return nil }
    guard let cursorLine = AXAttr.line(forIndex: cursorPos, in: element) else {
      logger.debug("[CFRangeLines] AXLineForIndex(cursorPos) returned nil")
      return nil
    }
    logger.debug(
      "[CFRangeLines] AXLineForIndex(\(cursorPos, privacy: .public))=\(cursorLine, privacy: .public)"
    )

    var collected: [String] = []
    var collectedLength = 0
    var idx = cursorLine
    var iterations = 0
    while idx >= 0, collectedLength < lookback, iterations < maxIterations {
      iterations += 1
      guard let lineRange = AXAttr.cfRange(forLine: idx, in: element) else {
        logger.debug("[CFRangeLines] AXRangeForLine(\(idx, privacy: .public))=<n/a>")
        break
      }
      logger.debug(
        """
        [CFRangeLines] line[\(idx, privacy: .public)] \
        AXRangeForLine location=\(lineRange.location, privacy: .public) \
        length=\(lineRange.length, privacy: .public)
        """
      )

      let queryRange: CFRange
      if idx == cursorLine {
        let truncated = max(0, cursorPos - lineRange.location)
        queryRange = CFRange(location: lineRange.location, length: truncated)
      } else {
        queryRange = lineRange
      }

      if let text = AXAttr.string(forRange: queryRange, in: element) {
        let kind = idx == cursorLine ? "lineStart..cursor" : "fullLine"
        logger.debug(
          """
          [CFRangeLines] line[\(idx, privacy: .public)] (\(kind, privacy: .public)) \
          len=\(text.utf16.count, privacy: .public) text=\(text, privacy: .private)
          """
        )
        collected.append(text)
        collectedLength += text.utf16.count
      } else {
        logger.debug("[CFRangeLines] line[\(idx, privacy: .public)] AXStringForRange=<n/a>")
        break
      }
      idx -= 1
    }

    guard !collected.isEmpty else { return nil }
    return collected.reversed().joined()
  }

  // MARK: - Private

  private static func describe<T>(_ v: T?) -> String {
    if let v { return "\(v)" }
    return "<n/a>"
  }
}
