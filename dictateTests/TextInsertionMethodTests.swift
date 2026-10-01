import Foundation
import Testing
@testable import L_Alfred


@MainActor
struct TextInsertionMethodTests {
  @Test func shortTextIsOneChunk() {
    #expect(TextInsertionMethod.keystrokeChunks(of: "Hello world") == ["Hello world"])
  }

  @Test func lineBreaksAreTheirOwnChunk() {
    #expect(TextInsertionMethod.keystrokeChunks(of: "one\ntwo\r\nthree") == ["one", "\n", "two", "\n", "three"])
  }

  @Test func chunksStayWithinTheEventLimit() {
    let chunks = TextInsertionMethod.keystrokeChunks(of: String(repeating: "a", count: 45))
    #expect(chunks.map(\.count) == [20, 20, 5])
  }

  @Test func neverSplitsAnEmoji() {
    // 19 letters + a 2-unit emoji would be 21 units: the emoji moves to the next chunk.
    let chunks = TextInsertionMethod.keystrokeChunks(of: String(repeating: "a", count: 19) + "😀b")
    #expect(chunks == [String(repeating: "a", count: 19), "😀b"])
    #expect(chunks.allSatisfy { $0.utf16.count <= TextInsertionMethod.maxUnitsPerEvent })
  }

  @Test func unknownStoredValueFallsBackToDefault() {
    let defaults = UserDefaults(suiteName: "TextInsertionMethodTests")!
    defaults.set("somethingRemoved", forKey: AppDefaultsKey.textInsertionMethod)
    #expect(TextInsertionMethod.current(in: defaults) == .default)
    defaults.removePersistentDomain(forName: "TextInsertionMethodTests")
  }
}
