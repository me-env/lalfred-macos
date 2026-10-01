import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


/// Reads only the text the cursor context needs, paragraph by paragraph, via AXTextMarker SPI:
///
///   - `AXParagraphTextMarkerRangeForTextMarker(cursor)` → the cursor's paragraph
///   - `AXStringForTextMarkerRange(start..cursor)`       → its text up to the cursor
///   - `AXPreviousTextMarkerForTextMarker(start)`        → a marker in the previous paragraph
///
/// Earlier paragraphs are only read while everything so far is whitespace, and are joined
/// with "\n" here because Chromium drops paragraph breaks from cross-paragraph ranges. The
/// cost depends on paragraph sizes, not on the document: ~0.2 ms in a 300k-character
/// Outlook thread, where walking the children took ~330 ms.
enum TextMarkerParagraphStrategy {
  private static let maxParagraphs = 50

  static func run(in element: AXUIElement, lookback: Int) -> String? {
    guard let cursor = AXMarker.cursor(in: element),
          let cursorParagraph = AXMarker.paragraphRange(for: cursor, in: element),
          var paragraphStart = AXMarker.startMarker(of: cursorParagraph)
    else {
      logger.debug("[TextMarkerParagraphs] cursor or paragraph range unavailable")
      return nil
    }
    var prefix = string(from: paragraphStart, to: cursor, in: element) ?? ""

    var paragraphs = 0
    while !prefix.contains(where: { !$0.isWhitespace }), prefix.utf16.count < lookback,
          paragraphs < maxParagraphs {
      paragraphs += 1
      guard let lastCharOfPrevious = AXMarker.previous(before: paragraphStart, in: element),
            isInside(lastCharOfPrevious, element),
            let previous = AXMarker.paragraphRange(for: lastCharOfPrevious, in: element),
            let previousStart = AXMarker.startMarker(of: previous),
            !CFEqual(previousStart as CFTypeRef, paragraphStart as CFTypeRef)
      else { break }  // First paragraph of the field.

      var text = AXMarker.string(forRange: previous, in: element) ?? ""
      while let last = text.last, last.isNewline { text.removeLast() }
      prefix = text + "\n" + prefix
      paragraphStart = previousStart
    }

    logger.debug(
      "[TextMarkerParagraphs] paragraphs=\(paragraphs + 1, privacy: .public) len=\(prefix.utf16.count, privacy: .public) text=\(prefix, privacy: .private)"
    )
    return prefix
  }

  // MARK: - Private

  private static func string(from start: AnyObject, to end: AnyObject, in element: AXUIElement) -> String? {
    AXMarker.createRange(from: start, to: end).flatMap { AXMarker.string(forRange: $0, in: element) }
  }

  /// Whether `marker` points into `element` or one of its descendants, so the walk stops
  /// at the field's first paragraph instead of reading the page around it.
  private static func isInside(_ marker: AnyObject, _ element: AXUIElement) -> Bool {
    var current = AXMarker.owner(of: marker, in: element)
    for _ in 0..<40 {
      guard let node = current else { return false }
      if CFEqual(node, element) { return true }
      current = AXAttr.getParent(in: node)
    }
    return false
  }
}
