import Foundation
import os

private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PasteTextTransformer")


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
    return String(firstChar).lowercased() + text.dropFirst()
  }

  private static func applyLeadingSpaceIfTouchingPreviousWord(
    _ text: String,
    context: CursorTextContext
  ) -> String {
    guard let prev = context.previousCharacter,
          !prev.isWhitespace,
          let firstChar = text.first,
          !firstChar.isWhitespace else {
      return text
    }
    return " " + text
  }
}
