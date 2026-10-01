import ApplicationServices
import Foundation


/// What a method read around the cursor.
struct CursorReading: Equatable {
  let textBeforeCursor: String
  /// `nil` when the method only reads up to the cursor.
  let textAfterCursor: String?

  var context: CursorTextContext {
    CursorTextContext(textBeforeCursor: textBeforeCursor)
  }
}


/// One way of reading the text around the cursor. ``CursorContextRules`` decides which
/// ones to try for a given element; the inspector runs all of them side by side.
///
/// Adding a method: add a case, give it a `displayName` + `summary`, and a line in `read`.
enum CursorContextMethod: String, CaseIterable, Codable, Sendable {
  case nativeValue
  case childrenTreeWalk
  case textMarkerParagraphs
  case textMarkerSelection
  case cfRangeLines
  case textMarkerLineByIndex
  case textMarkerLineWalk
  /// Reads nothing: the field is known to be empty whatever its `AXValue` says.
  case emptyField

  /// How far back the prefix-only methods read.
  static let lookback = 500

  /// Also the key of this method's reading in saved snapshots, so don't rename.
  var displayName: String {
    switch self {
    case .nativeValue: "AXValue + AXSelectedTextRange"
    case .childrenTreeWalk: "Children tree walk"
    case .textMarkerParagraphs: "TextMarker paragraphs"
    case .textMarkerSelection: "TextMarker selection"
    case .cfRangeLines: "CFRange line by line"
    case .textMarkerLineByIndex: "TextMarker line by index"
    case .textMarkerLineWalk: "TextMarker line walk"
    case .emptyField: "Empty field"
    }
  }

  var summary: String {
    switch self {
    case .nativeValue: "Full AXValue split at the selection start."
    case .childrenTreeWalk: "Rebuilds lines from AXStaticText children, correcting Chromium's offsets. Slow on big documents."
    case .textMarkerParagraphs: "Reads the cursor's paragraph (and earlier ones while blank) via text markers. Fast at any size."
    case .textMarkerSelection: "AXStringForTextMarkerRange(AXStartTextMarker..cursor). Can span the whole page."
    case .cfRangeLines: "AXLineForIndex + AXRangeForLine + AXStringForRange. Lines joined without \\n."
    case .textMarkerLineByIndex: "AXLineForTextMarker + AXTextMarkerRangeForLine. Lines joined without \\n."
    case .textMarkerLineWalk: "AXPreviousLineStartTextMarkerForTextMarker walk. Lines joined without \\n."
    case .emptyField: "Treats the field as empty (placeholder text exposed as value)."
    }
  }

  /// Reading of methods that don't look at the element, so saved snapshots can replay
  /// them even if they predate the method.
  var constantReading: CursorReading? {
    switch self {
    case .emptyField: CursorReading(textBeforeCursor: "", textAfterCursor: "")
    default: nil
    }
  }

  /// Reads `element` with this method, `nil` when the element doesn't support it.
  func read(_ element: AXUIElement) -> CursorReading? {
    if let constantReading { return constantReading }
    let reader = CursorContextReader()
    let cursorPos = AXAttr.cursorLocation(in: element)

    switch self {
    case .nativeValue:
      return cursorPos.flatMap { reader.getNativeRawContext(element: element, cursorPos: $0) }.map(Self.reading)
    case .childrenTreeWalk:
      return cursorPos.flatMap { reader.getRawContextFromAnalysis(in: element, naiveCursorPos: $0) }.map(Self.reading)
    case .textMarkerParagraphs:
      return TextMarkerParagraphStrategy.run(in: element, lookback: Self.lookback).map(Self.reading)
    case .textMarkerSelection:
      return TextMarkerSelectionStrategy.run(in: element, lookback: Self.lookback).map(Self.reading)
    case .cfRangeLines:
      return CFRangeLineByLineStrategy.run(in: element, cursorPos: cursorPos, lookback: Self.lookback).map(Self.reading)
    case .textMarkerLineByIndex:
      return TextMarkerLineByIndexStrategy.run(in: element, lookback: Self.lookback).map(Self.reading)
    case .textMarkerLineWalk:
      return TextMarkerLineWalkStrategy.run(in: element, lookback: Self.lookback).map(Self.reading)
    case .emptyField:
      return nil  // Handled by `constantReading`.
    }
  }

  private static func reading(_ raw: RawCursorTextContext) -> CursorReading {
    CursorReading(textBeforeCursor: String(raw.textBeforeCursor), textAfterCursor: String(raw.textAfterCursor))
  }

  private static func reading(_ prefix: String) -> CursorReading {
    CursorReading(textBeforeCursor: prefix, textAfterCursor: nil)
  }
}
