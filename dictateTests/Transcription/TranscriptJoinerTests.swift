import Testing
@testable import L_Alfred

struct TranscriptJoinerTests {
  @Test func joinsWithOneSpace() {
    #expect(TranscriptJoiner.join(["Hello there. ", "\nHow are you?"]) == "Hello there. How are you?")
  }

  @Test func dropsEmptySegments() {
    #expect(TranscriptJoiner.join(["", "First.", "  ", "Second."]) == "First. Second.")
    #expect(TranscriptJoiner.join([" ", ""]) == "")
  }

  @Test func addsNoSpaceBetweenScriptsWrittenWithoutSpaces() {
    #expect(TranscriptJoiner.join(["你好。", "我很好"]) == "你好。我很好")
    #expect(TranscriptJoiner.join(["こんにちは", "元気です"]) == "こんにちは元気です")
    #expect(TranscriptJoiner.join(["你好", "OK"]) == "你好 OK")
  }

  @Test func continuesASentenceInLowercase() {
    #expect(TranscriptJoiner.join(["We went to the", "Store later."]) == "We went to the store later.")
    #expect(TranscriptJoiner.join(["First, then", "Second, then", "Third."]) == "First, then second, then third.")
  }

  @Test func keepsTheCapitalAfterAFinishedSentence() {
    #expect(TranscriptJoiner.join(["Done.", "Next one"]) == "Done. Next one")
    #expect(TranscriptJoiner.join(["Really?", "Yes"]) == "Really? Yes")
    #expect(TranscriptJoiner.join(["Wait!", "Now"]) == "Wait! Now")
    #expect(TranscriptJoiner.join(["Well…", "Maybe"]) == "Well… Maybe")
    #expect(TranscriptJoiner.join(["He said \"Done.\"", "Then left"]) == "He said \"Done.\" Then left")
  }

  @Test func keepsCapitalizedWords() {
    #expect(TranscriptJoiner.join(["It's", "OK, fine."]) == "It's OK, fine.")
    #expect(TranscriptJoiner.join(["We called the", "API twice."]) == "We called the API twice.")
    #expect(TranscriptJoiner.join(["and then", "I left."]) == "and then I left.")
    #expect(TranscriptJoiner.join(["and then", "I'm gone."]) == "and then I'm gone.")
    #expect(TranscriptJoiner.join(["and then", "I’ll go."]) == "and then I’ll go.")
    #expect(TranscriptJoiner.join(["We flew to", "Paris yesterday."]) == "We flew to Paris yesterday.")
  }

  @Test func keepsTheCapitalOfProperNouns() {
    #expect(TranscriptJoiner.join(["Ask", "Lalfred about it."], properNouns: ["Lalfred"]) == "Ask Lalfred about it.")
    #expect(TranscriptJoiner.join(["Ask", "Lalfred about it."]) == "Ask lalfred about it.")
  }

  @Test func leavesScriptsWithoutCaseUnchanged() {
    #expect(TranscriptJoiner.join(["你好", "我很好"]) == "你好我很好")
    #expect(TranscriptJoiner.join(["今日は", "OK"]) == "今日は OK")
  }

  @Test func skipsEmptySegmentsWhenContinuing() {
    #expect(TranscriptJoiner.join(["We went to the", " ", "", "Store."]) == "We went to the store.")
    #expect(TranscriptJoiner.join(["", "Store."]) == "Store.")
  }
}
