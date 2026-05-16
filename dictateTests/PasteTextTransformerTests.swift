import Foundation
import Testing
@testable import L_Alfred


struct PasteTextTransformerTests {
  @Test func returnsTextUnchangedWhenNoContext() {
    let result = PasteTextTransformer.transform("Hello world", context: nil)
    #expect(result == "Hello world")
  }

  @Test func returnsEmptyTextUnchanged() {
    let result = PasteTextTransformer.transform(
      "",
      context: CursorTextContext(previousCharacter: "o", previousNonWhitespaceCharacter: "o")
    )
    #expect(result == "")
  }

  @Test func keepsCapitalizationAfterSentenceTerminatorWithSpace() {
    let result = PasteTextTransformer.transform(
      "Hello world",
      context: CursorTextContext(previousCharacter: " ", previousNonWhitespaceCharacter: ".")
    )
    #expect(result == "Hello world")
  }

  @Test func keepsCapitalizationAfterQuestionMark() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: " ", previousNonWhitespaceCharacter: "?")
    )
    #expect(result == "Hello")
  }

  @Test func keepsCapitalizationAfterSlash() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: "/", previousNonWhitespaceCharacter: "/")
    )
    #expect(result == " Hello")
  }

  @Test func keepsCapitalizationAfterExclamation() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: " ", previousNonWhitespaceCharacter: "!")
    )
    #expect(result == "Hello")
  }

  @Test func lowercasesWhenPreviousNonWhitespaceIsLetter() {
    let result = PasteTextTransformer.transform(
      "Hello world",
      context: CursorTextContext(previousCharacter: " ", previousNonWhitespaceCharacter: "o")
    )
    #expect(result == "hello world")
  }

  @Test func lowercasesWhenPreviousNonWhitespaceIsComma() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: " ", previousNonWhitespaceCharacter: ",")
    )
    #expect(result == "hello")
  }

  @Test func prependsSpaceAndLowercasesWhenStuckToPreviousLetter() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: "o", previousNonWhitespaceCharacter: "o")
    )
    #expect(result == " hello")
  }

  @Test func prependsSpaceWhenStuckToDigit() {
    let result = PasteTextTransformer.transform(
      "items",
      context: CursorTextContext(previousCharacter: "5", previousNonWhitespaceCharacter: "5")
    )
    #expect(result == " items")
  }

  @Test func doesNotPrependSpaceWhenAlreadyStartsWithSpace() {
    let result = PasteTextTransformer.transform(
      " hello",
      context: CursorTextContext(previousCharacter: "o", previousNonWhitespaceCharacter: "o")
    )
    #expect(result == " hello")
  }

  @Test func prependsSpaceWhenStuckToCommaAndLowercases() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: ",", previousNonWhitespaceCharacter: ",")
    )
    #expect(result == " hello")
  }

  @Test func prependsSpaceWhenStuckToDotAndKeepsCapitalization() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: ".", previousNonWhitespaceCharacter: ".")
    )
    #expect(result == " Hello")
  }

  @Test func prependsSpaceWhenStuckToColon() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(previousCharacter: ":", previousNonWhitespaceCharacter: ":")
    )
    #expect(result == " hello")
  }

  @Test func doesNotPrependSpaceWhenAtStartOfField() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: .empty
    )
    #expect(result == "Hello")
  }

  @Test func doesNotLowercaseWhenFirstCharIsAlreadyLowercase() {
    let result = PasteTextTransformer.transform(
      "hello",
      context: CursorTextContext(previousCharacter: "o", previousNonWhitespaceCharacter: "o")
    )
    #expect(result == " hello")
  }

  @Test func keepsCapitalizationWhenLineBreakBeforeCursor() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(
        previousCharacter: "\n",
        previousNonWhitespaceCharacter: "o",
        hasLineBreakBeforeCursor: true
      )
    )
    #expect(result == "Hello")
  }

  @Test func keepsCapitalizationAfterCarriageReturn() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(
        previousCharacter: "\r",
        previousNonWhitespaceCharacter: "o",
        hasLineBreakBeforeCursor: true
      )
    )
    #expect(result == "Hello")
  }

  @Test func keepsCapitalizationAfterUnicodeLineSeparator() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(
        previousCharacter: "\u{2028}",
        previousNonWhitespaceCharacter: "o",
        hasLineBreakBeforeCursor: true
      )
    )
    #expect(result == "Hello")
  }

  @Test func doesNotPrependSpaceAfterLineBreak() {
    let result = PasteTextTransformer.transform(
      "Hello",
      context: CursorTextContext(
        previousCharacter: "\n",
        previousNonWhitespaceCharacter: "o",
        hasLineBreakBeforeCursor: true
      )
    )
    #expect(result == "Hello")
  }
}
