import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// "Native field" path. Reads via the public CFRange-based AX API — the way a regular
/// `NSTextField` / `NSTextView` / real `<textarea>` exposes its content:
///
///   - `kAXValueAttribute`              → the full string
///   - `kAXNumberOfCharactersAttribute` → total char count
///   - `kAXSelectedTextRangeAttribute`  → cursor / selection (CFRange)
///   - `kAXSelectedTextAttribute`       → currently selected text
///   - `kAXStringForRangeParameterizedAttribute` → text for an arbitrary CFRange
///
/// Logs every raw value it can read. Returns the raw `AXStringForRange(0, cursorPos)`
/// result with no post-processing — this is purely for debugging.
enum NativeCFRangeStrategy {

  static func run(in element: AXUIElement, cursorPos: Int?, lookback _: Int) -> String? {
    logger.debug("[NativeCFRange] === Native CFRange path ===")

    let total = AXAttr.int(kAXNumberOfCharactersAttribute, in: element)
    let value = AXAttr.string(kAXValueAttribute, in: element)
    let valueLen = value?.utf16.count
    let selectedText = AXAttr.string(kAXSelectedTextAttribute, in: element)
    let selRange = AXAttr.selectedRange(in: element)

    logger.debug(
      """
      [NativeCFRange] AXNumberOfCharacters=\(describe(total), privacy: .public) \
      AXValue.len=\(describe(valueLen), privacy: .public) \
      cursorPos=\(describe(cursorPos), privacy: .public)
      """
    )
    if let r = selRange {
      logger.debug(
        """
        [NativeCFRange] AXSelectedTextRange location=\(r.location, privacy: .public) \
        length=\(r.length, privacy: .public)
        """
      )
    } else {
      logger.debug("[NativeCFRange] AXSelectedTextRange=<n/a>")
    }
    logger.debug(
      "[NativeCFRange] AXSelectedText=\(selectedText ?? "<n/a>", privacy: .private)"
    )

    if let v = value {
      logger.debug("[NativeCFRange] AXValue=\(v, privacy: .private)")
      logger.debug(
        "[NativeCFRange] AXValue codepoints=[\(codepoints(of: v), privacy: .public)]"
      )
    } else {
      logger.debug("[NativeCFRange] AXValue=<n/a>")
    }

    if let total {
      logStringForRange(in: element, label: "WHOLE", location: 0, length: total)
    }
    if let cursorPos, cursorPos > 0 {
      logStringForRange(in: element, label: "PREFIX", location: 0, length: cursorPos)
    }
    if let total, let cursorPos, cursorPos < total {
      logStringForRange(
        in: element, label: "SUFFIX", location: cursorPos, length: total - cursorPos
      )
    }

    guard let cursorPos, cursorPos > 0 else { return nil }
    let range = CFRange(location: 0, length: cursorPos)
    return AXAttr.string(forRange: range, in: element)
  }

  // MARK: - Private

  private static func logStringForRange(
    in element: AXUIElement, label: String, location: Int, length: Int
  ) {
    let range = CFRange(location: location, length: length)
    if let s = AXAttr.string(forRange: range, in: element) {
      logger.debug(
        """
        [NativeCFRange] AXStringForRange(\(location, privacy: .public),\
        \(length, privacy: .public)) [\(label, privacy: .public)] \
        len=\(s.utf16.count, privacy: .public) content=\(s, privacy: .private)
        """
      )
    } else {
      logger.debug(
        """
        [NativeCFRange] AXStringForRange(\(location, privacy: .public),\
        \(length, privacy: .public)) [\(label, privacy: .public)] unavailable
        """
      )
    }
  }

  private static func codepoints(of s: String) -> String {
    s.unicodeScalars
      .map { String(format: "U+%04X", $0.value) }
      .joined(separator: ",")
  }

  private static func describe<T>(_ v: T?) -> String {
    if let v { return "\(v)" }
    return "<n/a>"
  }
}
