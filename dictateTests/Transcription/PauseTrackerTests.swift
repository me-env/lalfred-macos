import Testing
@testable import L_Alfred

struct PauseTrackerTests {
  private static let speechEnergy = 1_000_000.0
  private static let quietEnergy = 10.0
  private static let twentySeconds = 320_000

  private func window(_ index: Int, startingAt start: Int, confidence: Double) -> SpeechWindow {
    SpeechWindow(samples: start + index * 4_000 ..< start + index * 4_000 + 8_000, speechConfidence: confidence)
  }

  /// Feeds windows of 0.5 s every 0.25 s from `start` in a segment starting at 0, and returns the
  /// first pause reported.
  private func firstPause(confidences: [Double], energies: [Double]? = nil, startingAt start: Int = twentySeconds) -> Range<Int>? {
    var tracker = PauseTracker()
    return firstPause(of: &tracker, confidences: confidences, energies: energies, startingAt: start)
  }

  private func firstPause(of tracker: inout PauseTracker, confidences: [Double], energies: [Double]? = nil, startingAt start: Int) -> Range<Int>? {
    for (index, confidence) in confidences.enumerated() {
      let energy = energies?[index] ?? (confidence >= 0.7 ? Self.speechEnergy : Self.quietEnergy)
      if let pause = tracker.pause(after: window(index, startingAt: start, confidence: confidence), energy: energy) { return pause }
    }
    return nil
  }

  @Test func reportsThreeSecondsOfSilenceAfterSpeechFromTwentySeconds() {
    // Speech windows end at 21.25 s; silent windows from 21 s to 24 s.
    let pause = firstPause(confidences: [0.9, 0.9, 0.9, 0.9] + Array(repeating: 0.1, count: 11))

    #expect(pause == 336_000 ..< 384_000)
  }

  @Test func threeSecondsOfSilenceBeforeTwentySecondsIsNoPause() {
    let confidences = [0.9, 0.9, 0.9, 0.9] + Array(repeating: 0.1, count: 11) + [0.9]

    #expect(firstPause(confidences: confidences, startingAt: 0) == nil)
  }

  @Test func shortPauseAcrossTheTwentySecondMarkCutsAfterIt() {
    // Speech from 18 s; silent windows from 19 s to 22 s.
    let pause = firstPause(confidences: [0.9, 0.9, 0.9, 0.9] + Array(repeating: 0.1, count: 11), startingAt: 288_000)

    #expect(pause == Self.twentySeconds ..< 352_000)
  }

  @Test func reportsFiveSecondsOfSilenceAfterSpeechAtAnyLength() {
    // Speech windows end at 1.25 s; silent windows from 1 s to 6 s.
    let pause = firstPause(confidences: [0.9, 0.9, 0.9, 0.9] + Array(repeating: 0.1, count: 19), startingAt: 0)

    #expect(pause == 16_000 ..< 96_000)
  }

  @Test func ignoresSilenceShorterThanThreeSeconds() {
    #expect(firstPause(confidences: [0.9, 0.9] + Array(repeating: 0.1, count: 10) + [0.9]) == nil)
  }

  @Test func ignoresSilenceWithoutSpeechBefore() {
    #expect(firstPause(confidences: Array(repeating: 0.1, count: 30), startingAt: 0) == nil)
    #expect(firstPause(confidences: Array(repeating: 0.5, count: 4) + Array(repeating: 0.1, count: 30)) == nil)
  }

  @Test func ambiguousWindowsBreakTheSilence() {
    let confidences = [0.9, 0.9] + Array(repeating: 0.1, count: 6) + [0.5] + Array(repeating: 0.1, count: 12)

    #expect(firstPause(confidences: confidences) == nil)
  }

  @Test func ignoresSilentWindowsAsLoudAsTheSpeech() {
    let confidences = [0.9, 0.9] + Array(repeating: 0.1, count: 30)

    #expect(firstPause(confidences: confidences, energies: Array(repeating: Self.speechEnergy, count: 32)) == nil)
  }

  @Test func unknownEnergyBreaksTheSilence() {
    var tracker = PauseTracker()
    _ = tracker.pause(after: SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.9), energy: Self.speechEnergy)
    _ = tracker.pause(after: SpeechWindow(samples: 4_000 ..< 12_000, speechConfidence: 0.1), energy: Self.quietEnergy)

    _ = tracker.pause(after: SpeechWindow(samples: 8_000 ..< 16_000, speechConfidence: 0.1), energy: nil)

    #expect(tracker.silence == nil)
  }

  @Test func aNewSegmentNeedsItsOwnSpeechBeforeAPause() {
    var tracker = PauseTracker()
    let pause = firstPause(of: &tracker, confidences: [0.9, 0.9] + Array(repeating: 0.1, count: 19), startingAt: 0)
    let cut = pause.map { $0.lowerBound + $0.count / 2 } ?? 0

    tracker.startSegment(at: cut)
    let pauseAfterCut = firstPause(of: &tracker, confidences: Array(repeating: 0.1, count: 60), startingAt: 88_000)

    #expect(pause != nil)
    #expect(pauseAfterCut == nil)
  }

  @Test func silenceAfterACutIsJudgedByTheSpeechBeforeIt() {
    var tracker = PauseTracker()
    let silent = SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.1)
    #expect(!tracker.isClearlySilent(silent, energy: Self.quietEnergy))

    _ = tracker.pause(after: SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.9), energy: Self.speechEnergy)
    tracker.startSegment(at: 100_000)

    #expect(tracker.isClearlySilent(silent, energy: Self.quietEnergy))
    #expect(!tracker.isClearlySilent(silent, energy: Self.speechEnergy))
    #expect(!tracker.isClearlySilent(SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.5), energy: Self.quietEnergy))
    #expect(!tracker.isClearlySilent(silent, energy: nil))
  }
}
