import Foundation
import Testing
@testable import L_Alfred

struct AudioSegmenterTests {
  private static let captureChunkSizes = [1_600, 3_200, 1_602, 4_798, 640]

  private func segment(_ recording: TestRecording, chunkSizes: [Int] = captureChunkSizes) -> (segments: [Data], factory: FakeDetectorFactory) {
    let factory = FakeDetectorFactory(recording: recording)
    var segmenter = AudioSegmenter(makeDetector: factory.make)
    var actions: [AudioSegmenter.Action] = []
    for chunk in chunked(recording.pcm, sizes: chunkSizes) {
      actions += segmenter.append(chunk)
    }
    actions += segmenter.finish()
    return (segments(of: actions), factory)
  }

  /// Recording positions where each segment after the first starts.
  private func cutPositions(of segments: [Data]) -> [Int] {
    segments.dropLast().reduce(into: [Int]()) { cuts, segment in
      cuts.append((cuts.last ?? 0) + segment.count / 2)
    }
  }

  @Test func noCutBeforeTwentySeconds() {
    let recording = TestRecording(duration: 30, pauses: [5 ..< 6, 12 ..< 14, 19 ..< 19.9, 24 ..< 25])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { seconds($0) >= 20 })
    #expect(result.factory.created.compactMap(\.firstPositionFed).allSatisfy { seconds($0) >= 20 })
  }

  @Test func shortDictationIsOneSegmentWithoutDetector() {
    let recording = TestRecording(duration: 15, pauses: [5 ..< 7])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
    #expect(result.factory.created.isEmpty)
  }

  @Test func neverCutsDuringSpeech() {
    let recording = TestRecording(duration: 75, pauses: [])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func cutLandsInsideThePause() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 25.8])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { recording.pauseSamples[0].contains($0) })
  }

  @Test func eachSegmentLastsAtLeastTwentySeconds() {
    let recording = TestRecording(duration: 70, pauses: [22 ..< 23, 30 ..< 31, 44 ..< 45, 60 ..< 61])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.map { Int(seconds($0)) } == [22, 44])
  }

  @Test func everyByteGoesToExactlyOneSegment() {
    let recording = TestRecording(duration: 90, pauses: [21 ..< 22, 43 ..< 44, 70 ..< 71])

    for chunkSizes in [Self.captureChunkSizes, [32], [7_998, 30_002], [recording.pcm.count]] {
      let result = segment(recording, chunkSizes: chunkSizes)

      #expect(result.segments.count == 4)
      #expect(result.segments.reduce(Data(), +) == recording.pcm)
    }
  }

  @Test func wholeRecordingInOneChunkIsCutLikeAStream() {
    let recording = TestRecording(duration: 90, pauses: [21 ..< 22, 43 ..< 44, 70 ..< 71])

    let streamed = segment(recording)
    let atOnce = segment(recording, chunkSizes: [recording.pcm.count])

    #expect(atOnce.segments == streamed.segments)
  }

  @Test func withoutDetectorTheRecordingIsOneSegment() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 26])
    var segmenter = AudioSegmenter(makeDetector: { nil })

    var actions: [AudioSegmenter.Action] = []
    for chunk in chunked(recording.pcm, sizes: Self.captureChunkSizes) {
      actions += segmenter.append(chunk)
    }

    #expect(!actions.contains(.cut))
    #expect(segments(of: actions + segmenter.finish()) == [recording.pcm])
  }

  @Test func holdsBackUnderASecondWhileSearching() {
    let recording = TestRecording(duration: 40, pauses: [])
    var segmenter = AudioSegmenter(makeDetector: FakeDetectorFactory(recording: recording).make)

    var sentByteCount = 0
    for chunk in chunked(recording.pcm, sizes: [3_200]) {
      sentByteCount += segments(of: segmenter.append(chunk)).reduce(0) { $0 + $1.count }
    }

    let heldBackSeconds = seconds((recording.pcm.count - sentByteCount) / 2)
    #expect(heldBackSeconds < 1)
  }
}
