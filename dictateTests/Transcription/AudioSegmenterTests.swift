import Foundation
import Testing
@testable import L_Alfred

struct AudioSegmenterTests {
  private static let captureChunkSizes = [1_600, 3_200, 1_602, 4_798, 640]

  private func segment(
    _ recording: TestRecording,
    chunkSizes: [Int] = captureChunkSizes,
    classifiedEnd: Int = .max
  ) -> (segments: [Data], factory: FakeDetectorFactory) {
    let factory = FakeDetectorFactory(recording: recording, classifiedEnd: classifiedEnd)
    var segmenter = AudioSegmenter(makeDetector: factory.make)
    var actions: [AudioSegmenter.Action] = []
    for chunk in chunked(recording.pcm, sizes: chunkSizes) {
      actions += segmenter.append(chunk)
    }
    actions += segmenter.finish()
    return (segments(of: actions), factory)
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

  @Test func threeSecondPausesCutOnlyFromTwentySeconds() {
    let recording = TestRecording(duration: 30, pauses: [5 ..< 8.5, 12 ..< 15.5, 19 ..< 19.9, 24 ..< 27.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { recording.pauseSamples[3].contains($0) })
  }

  @Test func threeSecondPauseAcrossTheTwentySecondMarkCutsAfterIt() {
    let recording = TestRecording(duration: 30, pauses: [18.5 ..< 22])

    let cuts = cutPositions(of: segment(recording).segments)

    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { seconds($0) >= 20 && recording.pauseSamples[0].contains($0) })
  }

  @Test func shortDictationWithShortPausesIsOneSegment() {
    let recording = TestRecording(duration: 15, pauses: [5 ..< 9])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func fiveSecondPauseCutsInsideItAtAnyLength() {
    let recording = TestRecording(duration: 15, pauses: [8 ..< 13.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(cuts.allSatisfy { recording.pauseSamples[0].contains($0) })
    #expect(result.segments.reduce(Data(), +) == recording.pcm)
  }

  @Test func fiveSecondsOfSilenceAtTheStartDoNotCut() {
    let recording = TestRecording(duration: 15, pauses: [0 ..< 6])

    #expect(segment(recording).segments == [recording.pcm])
  }

  @Test func fiveSecondPauseAfterUnclearAudioDoesNotCut() {
    let recording = TestRecording(duration: 16, pauses: [8 ..< 14], unclear: [0 ..< 8])

    #expect(segment(recording).segments == [recording.pcm])
  }

  @Test func detectorIsCreatedOncePerDictation() {
    let recording = TestRecording(duration: 90, pauses: [21 ..< 24.5, 45 ..< 48.5, 70 ..< 73.5])

    let result = segment(recording)

    #expect(result.segments.count == 4)
    #expect(result.factory.created.map(\.firstPositionFed) == [0])
  }

  @Test func neverCutsDuringSpeech() {
    let recording = TestRecording(duration: 75, pauses: [])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func pausesBetweenSentencesDoNotCut() {
    let recording = TestRecording(duration: 40, pauses: [2 ..< 4.9, 22 ..< 23, 26 ..< 28, 31 ..< 32.9])

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
    let longUnclear = TestRecording(duration: 40, pauses: [], unclear: [25 ..< 31])
    let brokenPause = TestRecording(duration: 40, pauses: [25 ..< 27.5, 28 ..< 30.5], unclear: [27.5 ..< 28])

    #expect(segment(longUnclear).segments == [longUnclear.pcm])
    #expect(segment(brokenPause).segments == [brokenPause.pcm])
  }

  @Test func silenceNotPrecededByConfidentSpeechDoesNotCut() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 31], unclear: [0 ..< 40])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func loudAudioClassifiedAsSilenceDoesNotCut() {
    let recording = TestRecording(duration: 40, pauses: [], missedSpeech: [8 ..< 14, 25 ..< 31])

    let result = segment(recording)

    #expect(result.segments == [recording.pcm])
  }

  @Test func eachSegmentCutByAShortPauseLastsAtLeastTwentySeconds() {
    let recording = TestRecording(duration: 75, pauses: [22 ..< 25.5, 30 ..< 33.5, 50 ..< 53.5, 60 ..< 63.5])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 2)
    #expect(recording.pauseSamples[0].contains(cuts[0]))
    #expect(recording.pauseSamples[2].contains(cuts[1]))
  }

  @Test func everyByteGoesToExactlyOneSegment() {
    let recording = TestRecording(duration: 90, pauses: [10 ..< 15.5, 40 ..< 43.5, 70 ..< 73.5])

    for chunkSizes in [Self.captureChunkSizes, [32], [7_998, 30_002], [recording.pcm.count]] {
      let result = segment(recording, chunkSizes: chunkSizes)

      #expect(result.segments.count == 4)
      #expect(result.segments.reduce(Data(), +) == recording.pcm)
    }
  }

  @Test func wholeRecordingInOneChunkIsCutLikeAStream() {
    let recording = TestRecording(duration: 90, pauses: [10 ..< 15.5, 40 ..< 43.5, 70 ..< 73.5])

    let streamed = segment(recording)
    let atOnce = segment(recording, chunkSizes: [recording.pcm.count])

    #expect(atOnce.segments == streamed.segments)
  }

  @Test func silenceAfterTheLastCutIsNotSent() {
    for recording in [TestRecording(duration: 40, pauses: [25 ..< 40]), TestRecording(duration: 20, pauses: [8 ..< 20])] {
      let result = segment(recording)

      let cuts = cutPositions(of: result.segments)
      #expect(result.segments.count == 2)
      #expect(result.segments.last == Data())
      #expect(result.segments[0] == recording.pcm.prefix(cuts[0] * 2))
      #expect(recording.pauseSamples.last?.contains(cuts[0]) == true)
    }
  }

  @Test func audioAfterTheLastCutIsSentWhenNotClearlySilent() {
    let ambiguous = TestRecording(duration: 30, pauses: [10 ..< 29], unclear: [29 ..< 30])
    let speech = TestRecording(duration: 30, pauses: [10 ..< 29.5])

    for recording in [ambiguous, speech] {
      let result = segment(recording)

      #expect(result.segments.count == 2)
      #expect(!result.segments[1].isEmpty)
      #expect(result.segments.reduce(Data(), +) == recording.pcm)
    }
  }

  @Test func silenceAfterTheLastCutIsSentWhenTooMuchIsUnclassified() {
    let recording = TestRecording(duration: 30, pauses: [10 ..< 30])

    let result = segment(recording, classifiedEnd: samples(atSecond: 29))

    #expect(result.segments.count == 2)
    #expect(result.segments.reduce(Data(), +) == recording.pcm)
  }

  @Test func silenceAfterACutIsSentWithTheSpeechFollowingIt() {
    let recording = TestRecording(duration: 40, pauses: [10 ..< 25])

    let result = segment(recording)

    let cuts = cutPositions(of: result.segments)
    #expect(cuts.count == 1)
    #expect(result.segments.reduce(Data(), +) == recording.pcm)
  }

  @Test func withoutDetectorTheRecordingIsOneSegment() {
    let recording = TestRecording(duration: 40, pauses: [25 ..< 31])
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

  @Test func holdsBackAPossibleShortPauseUntilItIsClassified() {
    let result = heldBackSeconds(TestRecording(duration: 40, pauses: [25 ..< 27.9]))

    #expect(result.cutCount == 0)
    #expect(result.maximum > 2.5)
    #expect(result.maximum < 4)
  }

  @Test func holdsBackAPossibleLongPauseUnderSixSeconds() {
    let result = heldBackSeconds(TestRecording(duration: 15, pauses: [5 ..< 9.9]))

    #expect(result.cutCount == 0)
    #expect(result.maximum > 4.5)
    #expect(result.maximum < 5.75)
  }
}
