import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// "Cursor context" path via the HIServices AXTextMarker SPI.
///
/// Reads everything around the cursor via opaque marker tokens (no character indices):
///
///   - `AXStartTextMarker`              → first marker in the element
///   - `AXEndTextMarker`                → last marker in the element
///   - `AXSelectedTextMarkerRange`      → marker range covering the current selection
///   - `AXStringForTextMarkerRange`     → text for an arbitrary marker range
///
/// Logs whether each capability is supported, the WHOLE / PREFIX / SUFFIX strings, and
/// returns the raw `AXStringForTextMarkerRange(start, cursor)` with no post-processing.
enum TextMarkerSelectionStrategy {

  static func run(in element: AXUIElement, lookback _: Int) -> String? {
    logger.debug("[TextMarkerSelection] === TextMarker (HIServices SPI) cursor-context path ===")

    let attrs = AXAttr.attributeNames(in: element)
    let params = AXAttr.parameterizedAttributeNames(in: element)

    let hasStart = attrs.contains("AXStartTextMarker")
    let hasEnd = attrs.contains("AXEndTextMarker")
    let hasSelectedRange = attrs.contains("AXSelectedTextMarkerRange")
    let hasStringForRange = params.contains("AXStringForTextMarkerRange")

    logger.debug(
      """
      [TextMarkerSelection] support: \
      AXStartTextMarker=\(hasStart, privacy: .public) \
      AXEndTextMarker=\(hasEnd, privacy: .public) \
      AXSelectedTextMarkerRange=\(hasSelectedRange, privacy: .public) \
      AXStringForTextMarkerRange=\(hasStringForRange, privacy: .public)
      """
    )

    guard hasStringForRange else { return nil }

    let startMarker = hasStart ? AXMarker.documentStart(in: element) : nil
    let endMarker = hasEnd ? AXMarker.documentEnd(in: element) : nil
    let cursorMarker = AXMarker.cursor(in: element)

    logger.debug(
      """
      [TextMarkerSelection] markers: \
      start=\(startMarker == nil ? "<n/a>" : "<got>", privacy: .public) \
      end=\(endMarker == nil ? "<n/a>" : "<got>", privacy: .public) \
      cursor=\(cursorMarker == nil ? "<n/a>" : "<got>", privacy: .public)
      """
    )

    if let startMarker, let endMarker {
      logMarkerRangeString(in: element, label: "WHOLE", from: startMarker, to: endMarker)
    }
    if let startMarker, let cursorMarker {
      logMarkerRangeString(in: element, label: "PREFIX", from: startMarker, to: cursorMarker)
    }
    if let cursorMarker, let endMarker {
      logMarkerRangeString(in: element, label: "SUFFIX", from: cursorMarker, to: endMarker)
    }

    guard let startMarker, let cursorMarker,
          let prefixRange = AXMarker.createRange(from: startMarker, to: cursorMarker)
    else { return nil }
    return AXMarker.string(forRange: prefixRange, in: element)
  }

  // MARK: - Private

  private static func logMarkerRangeString(
    in element: AXUIElement, label: String, from start: AnyObject, to end: AnyObject
  ) {
    guard let range = AXMarker.createRange(from: start, to: end) else {
      logger.debug(
        """
        [TextMarkerSelection] AXStringForTextMarkerRange [\(label, privacy: .public)] \
        range create failed
        """
      )
      return
    }
    if let s = AXMarker.string(forRange: range, in: element) {
      logger.debug(
        """
        [TextMarkerSelection] AXStringForTextMarkerRange [\(label, privacy: .public)] \
        len=\(s.utf16.count, privacy: .public) content=\(s, privacy: .private)
        """
      )
    } else {
      logger.debug(
        """
        [TextMarkerSelection] AXStringForTextMarkerRange [\(label, privacy: .public)] \
        unavailable
        """
      )
    }
  }
}
