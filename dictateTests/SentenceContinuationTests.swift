import Testing
@testable import L_Alfred

/// The paste at the cursor and the join of segments continue a sentence by the same rule.
struct SentenceContinuationTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let before: String
    let text: String
    let expected: String
    var properNouns: Set<String> = []

    var testDescription: String { "\(before) | \(text)" }
  }

  static let cases: [Case] = [
    Case(before: "We went to the", text: "Store later.", expected: "store later."),
    Case(before: "It's", text: "OK, fine.", expected: "OK, fine."),
    Case(before: "It's", text: "Ok, fine.", expected: "ok, fine."),
    Case(before: "We flew to the", text: "USA twice.", expected: "USA twice."),
    Case(before: "We called the", text: "API twice.", expected: "API twice."),
    Case(before: "and then", text: "I left.", expected: "I left."),
    Case(before: "and then", text: "I'm gone.", expected: "I'm gone."),
    Case(before: "and then", text: "I’ll go.", expected: "I’ll go."),
    Case(before: "and then", text: "If so.", expected: "if so."),
    Case(before: "We flew to", text: "Paris yesterday.", expected: "Paris yesterday."),
    Case(before: "Ask", text: "Lalfred about it.", expected: "Lalfred about it.", properNouns: ["Lalfred"]),
    Case(before: "Ask", text: "Lalfred about it.", expected: "lalfred about it."),
    Case(before: "Done.", text: "Next one", expected: "Next one"),
    Case(before: "Really?", text: "Yes", expected: "Yes"),
    Case(before: "Wait!", text: "Now", expected: "Now"),
    Case(before: "Well…", text: "Maybe", expected: "Maybe"),
  ]

  @Test(arguments: cases)
  func continuesTheSentenceWhenJoiningSegments(_ testCase: Case) {
    let joined = TranscriptJoiner.join([testCase.before, testCase.text], properNouns: testCase.properNouns)
    #expect(joined == testCase.before + " " + testCase.expected)
  }

  @Test(arguments: cases)
  func continuesTheSentenceWhenPasting(_ testCase: Case) {
    let pasted = PasteTextTransformer.transform(
      testCase.text,
      context: CursorTextContext(textBeforeCursor: testCase.before + " "),
      properNouns: testCase.properNouns
    )
    #expect(pasted == testCase.expected)
  }

  @Test func leavesTheStartOfATextAsTranscribed() {
    #expect(TranscriptJoiner.join(["", "Store."]) == "Store.")
    #expect(PasteTextTransformer.transform("Store.", context: .empty) == "Store.")
  }
}
