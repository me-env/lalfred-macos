import Foundation
import os

private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PasteTextTransformer")

struct RawCursorTextContext: Equatable, Hashable {
  let text: String
  let cursorPosition: Int
  
  /// Text up to the cursor. The cursor offset is in UTF-16 units (as AX reports it)
  /// and is clamped, since some apps report offsets past the end of `AXValue`.
  var textBeforeCursor: Substring {
    let offset = min(max(cursorPosition, 0), text.utf16.count)
    let index = String.Index(utf16Offset: offset, in: text)
    return text[..<index]
  }

  /// Text after the cursor, see ``textBeforeCursor``.
  var textAfterCursor: Substring {
    let offset = min(max(cursorPosition, 0), text.utf16.count)
    let index = String.Index(utf16Offset: offset, in: text)
    return text[index...]
  }
}

struct CursorTextContext: Equatable, Hashable {
  let previousCharacter: Character?
  let previousNonWhitespaceCharacter: Character?
  let hasLineBreakBeforeCursor: Bool

  init(
    previousCharacter: Character?,
    previousNonWhitespaceCharacter: Character?,
    hasLineBreakBeforeCursor: Bool = false
  ) {
    self.previousCharacter = previousCharacter
    self.previousNonWhitespaceCharacter = previousNonWhitespaceCharacter
    self.hasLineBreakBeforeCursor = hasLineBreakBeforeCursor
  }

  /// Zero-width characters editors insert to hold the caret, like the U+FEFF Slate puts
  /// in an empty line (Discord). They are invisible, so they don't count as text.
  private static let zeroWidthCharacters: Set<Character> = ["\u{FEFF}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}"]

  /// Derives the context from whatever text sits before the cursor.
  init<S: StringProtocol>(textBeforeCursor rawPrefix: S) {
    let prefix = rawPrefix.filter { !Self.zeroWidthCharacters.contains($0) }
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

    self.init(
      previousCharacter: prefix.last,
      previousNonWhitespaceCharacter: previousNonWhitespaceCharacter,
      hasLineBreakBeforeCursor: hasLineBreakBeforeCursor
    )
  }

  static let empty = CursorTextContext(
    previousCharacter: nil,
    previousNonWhitespaceCharacter: nil,
    hasLineBreakBeforeCursor: false
  )

  var description: String {
    "CursorTextContext(prev: \(previousCharacter.map { "'\($0)'" } ?? "nil"), prevNonWS: \(previousNonWhitespaceCharacter.map { "'\($0)'" } ?? "nil"), lineBreak: \(hasLineBreakBeforeCursor))"
  }
}


enum PasteTextTransformer {
  private static let sentenceTerminators: Set<Character> = [".", "!", "?", "/"]
  /// Characters that open a group and hug the text that follows, like "(hello".
  private static let openingCharacters: Set<Character> = ["(", "[", "{", "“", "‘"]

  static func transform(_ text: String, context: CursorTextContext?) -> String {
    logger.info("transform \(String(describing: context), privacy: .public)")
    
    guard !text.isEmpty, let context else { return text }

    var output = text
    output = applyLowercaseIfContinuingSentence(output, context: context)
    output = applyLeadingSpaceIfTouchingPreviousWord(output, context: context)
    return output
  }

  private static func applyLowercaseIfContinuingSentence(
    _ text: String,
    context: CursorTextContext
  ) -> String {
    guard let prevNonWS = context.previousNonWhitespaceCharacter,
          !context.hasLineBreakBeforeCursor,
          !sentenceTerminators.contains(prevNonWS),
          let firstChar = text.first,
          firstChar.isUppercase else {
      return text
    }
    if startsWithOK(text) { return "ok" + text.dropFirst(2) }
    return String(firstChar).lowercased() + text.dropFirst()
  }

  /// "OK" is the one all-caps word that should be lowercased as a whole ("ok", not "oK").
  private static func startsWithOK(_ text: String) -> Bool {
    guard text.hasPrefix("OK") else { return false }
    return !(text.dropFirst(2).first?.isLetter ?? false)
  }

  private static func applyLeadingSpaceIfTouchingPreviousWord(
    _ text: String,
    context: CursorTextContext
  ) -> String {
    guard let prev = context.previousCharacter,
          !prev.isWhitespace,
          !openingCharacters.contains(prev),
          let firstChar = text.first,
          !firstChar.isWhitespace else {
      return text
    }
    return " " + text
  }
}
