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
}
