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

  private func heldBackSeconds(_ recording: TestRecording) -> (maximum: Double, cutCount: Int) {
    var segmenter = AudioSegmenter(makeDetector: FakeDetectorFactory(recording: recording).make)
    var receivedByteCount = 0
    var sentByteCount = 0
    var maximumHeldBack = 0
    var cutCount = 0
    for chunk in chunked(recording.pcm, sizes: [3_200]) {
      let actions = segmenter.append(chunk)
      receivedByteCount += chunk.count
      sentByteCount += segments(of: actions).reduce(0) { $0 + $1.count }
      cutCount += actions.filter { $0 == .cut }.count
      maximumHeldBack = max(maximumHeldBack, receivedByteCount - sentByteCount)
    }
    return (seconds(maximumHeldBack / 2), cutCount)
  }

  @Test func noCutBeforeTwentySeconds() {
    let recording = TestRecording(duration: 30, pauses: [5 ..< 8.5, 12 ..< 15.5, 19 ..< 19.9, 24 ..< 27.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { seconds($0) >= 20 })
    #expect(result.factory.created.compactMap(\.firstPositionFed).allSatisfy { seconds($0) >= 20 })
  }

  @Test func shortDictationIsOneSegmentWithoutDetector() {
    let recording = TestRecording(duration: 15, pauses: [5 ..< 9])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
    #expect(result.factory.created.isEmpty)
  }

  @Test func neverCutsDuringSpeech() {
    let recording = TestRecording(duration: 75, pauses: [])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func pausesBetweenSentencesDoNotCut() {
    let recording = TestRecording(duration: 40, pauses: [22 ..< 23, 26 ..< 28, 31 ..< 32.9])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func threeSecondPauseAfterSpeechCutsInsideIt() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 28])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { recording.pauseSamples[0].contains($0) })
  }

  @Test func speechFadingOutBeforeThePauseStillCuts() {
    let recording = TestRecording(duration: 40, pauses: [25.5 ..< 29], unclear: [25 ..< 25.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { recording.pauseSamples[0].contains($0) })
  }

  @Test func ambiguousWindowsDoNotCountAsAPause() {
    let longUnclear = TestRecording(duration: 40, pauses: [], unclear: [25 ..< 29])
    let brokenPause = TestRecording(duration: 40, pauses: [25 ..< 26.5, 27 ..< 28.6], unclear: [26.5 ..< 27])

    #expect(segment(longUnclear).segments == [longUnclear.pcm])
    #expect(segment(brokenPause).segments == [brokenPause.pcm])
  }

  @Test func silenceNotPrecededByConfidentSpeechDoesNotCut() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 29], unclear: [0 ..< 40])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func loudAudioClassifiedAsSilenceDoesNotCut() {
    let recording = TestRecording(duration: 40, pauses: [], missedSpeech: [25 ..< 29])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func eachSegmentLastsAtLeastTwentySeconds() {
    let recording = TestRecording(duration: 75, pauses: [22 ..< 25.5, 30 ..< 33.5, 50 ..< 53.5, 60 ..< 63.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 2)
    #expect(recording.pauseSamples[0].contains(cuts[0]))
    #expect(recording.pauseSamples[2].contains(cuts[1]))
  }

  @Test func everyByteGoesToExactlyOneSegment() {
    let recording = TestRecording(duration: 90, pauses: [21 ..< 24.5, 45 ..< 48.5, 70 ..< 73.5])

    for chunkSizes in [Self.captureChunkSizes, [32], [7_998, 30_002], [recording.pcm.count]] {
      let result = segment(recording, chunkSizes: chunkSizes)

      #expect(result.segments.count == 4)
      #expect(result.segments.reduce(Data(), +) == recording.pcm)
    }
  }

  @Test func wholeRecordingInOneChunkIsCutLikeAStream() {
    let recording = TestRecording(duration: 90, pauses: [21 ..< 24.5, 45 ..< 48.5, 70 ..< 73.5])

    let streamed = segment(recording)
    let atOnce = segment(recording, chunkSizes: [recording.pcm.count])

    #expect(atOnce.segments == streamed.segments)
  }

  @Test func withoutDetectorTheRecordingIsOneSegment() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 29])
    var segmenter = AudioSegmenter(makeDetector: { nil })

    var actions: [AudioSegmenter.Action] = []
    for chunk in chunked(recording.pcm, sizes: Self.captureChunkSizes) {
      actions += segmenter.append(chunk)
    }

    #expect(!actions.contains(.cut))
    #expect(segments(of: actions + segmenter.finish()) == [recording.pcm])
  }

  @Test func holdsBackUnderASecondDuringSpeech() {
    let result = heldBackSeconds(TestRecording(duration: 40, pauses: []))

    #expect(result.maximum < 1)
  }

  @Test func holdsBackAPossiblePauseUntilItIsClassified() {
    let result = heldBackSeconds(TestRecording(duration: 40, pauses: [25 ..< 27.9]))

    #expect(result.cutCount == 0)
    #expect(result.maximum > 2.5)
    #expect(result.maximum < 4)
  }
}
