import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


protocol CursorContextReading {
  func readContext() -> CursorTextContext?
}

/// Reads cursor-adjacent text context from the system-wide focused element.
///
/// Currently in **debugging mode**: every strategy is invoked unconditionally so each
/// one logs its raw AX data. Each strategy lives in its own file under
/// `dictate/Utils/CursorContext/Strategies/` and is responsible for logging everything
/// it can pull from its API surface; the return values are intentionally raw (no
/// `\n` insertion or trimming) and used here only as a default for downstream code.
struct CursorContextReader: CursorContextReading {

  private let lookbackLimit = 64

  func readContext() -> CursorTextContext? {
    guard let element = AXAttr.copyFocusedElement() else {
      logger.info("[CursorContextReader] No focused element")
      return nil
    }

    let cursorPos = AXAttr.cursorLocation(in: element)
    logger.debug("[CursorContextReader] === Focused element ===")
    let role = AXAttr.string(kAXRoleAttribute, in: element) ?? "<none>"
    let subrole = AXAttr.string(kAXSubroleAttribute, in: element) ?? "<none>"
    let identifier = AXAttr.string(kAXIdentifierAttribute, in: element) ?? "<none>"
    logger.debug(
      """
      [CursorContextReader] role=\(role, privacy: .public) \
      subrole=\(subrole, privacy: .public) identifier=\(identifier, privacy: .public)
      """
    )

    // Run every strategy. Each one logs its own raw API output; the return values are
    // collected only so we can still produce a `CursorTextContext` for the caller.
    let native = NativeCFRangeStrategy.run(
      in: element, cursorPos: cursorPos, lookback: lookbackLimit
    )
    let textMarker = TextMarkerSelectionStrategy.run(
      in: element, lookback: lookbackLimit
    )
    let cfLines = CFRangeLineByLineStrategy.run(
      in: element, cursorPos: cursorPos, lookback: lookbackLimit
    )
    let markerLinesByIndex = TextMarkerLineByIndexStrategy.run(
      in: element, lookback: lookbackLimit
    )
    let markerLineWalk = TextMarkerLineWalkStrategy.run(
      in: element, lookback: lookbackLimit
    )

    // Pick the first non-nil as a default — we don't really care which one wins yet,
    // we're debugging.
    let prefix = native
      ?? textMarker
      ?? cfLines
      ?? markerLinesByIndex
      ?? markerLineWalk
      ?? ""
    return makeContext(prefix: prefix)
  }

  // MARK: - Private

  private func makeContext(prefix: String) -> CursorTextContext {
    if prefix.isEmpty { return .empty }

    var previousNonWhitespaceCharacter: Character? = nil
    var hasLineBreakBeforeCursor = false

    for ch in prefix.reversed() {
      if ch.isNewline {
        hasLineBreakBeforeCursor = true
      } else if !ch.isWhitespace {
        previousNonWhitespaceCharacter = ch
        break
      }
    }

    return CursorTextContext(
      previousCharacter: prefix.last,
      previousNonWhitespaceCharacter: previousNonWhitespaceCharacter,
      hasLineBreakBeforeCursor: hasLineBreakBeforeCursor
    )
  }
}
