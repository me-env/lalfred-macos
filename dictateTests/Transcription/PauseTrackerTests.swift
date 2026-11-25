import Testing
@testable import L_Alfred

struct PauseTrackerTests {
  private static let speechEnergy = 1_000_000.0
  private static let quietEnergy = 10.0

  /// Feeds windows of 0.5 s every 0.25 s, starting at 0, and returns the first pause reported.
  private func firstPause(confidences: [Double], energies: [Double]? = nil) -> Range<Int>? {
    var tracker = PauseTracker()
    for (index, confidence) in confidences.enumerated() {
      let window = SpeechWindow(samples: index * 4_000 ..< index * 4_000 + 8_000, speechConfidence: confidence)
      let energy = energies?[index] ?? (confidence >= 0.7 ? Self.speechEnergy : Self.quietEnergy)
      if let pause = tracker.pause(after: window, energy: energy) { return pause }
    }
    return nil
  }

  @Test func reportsThreeSecondsOfSilenceAfterSpeech() {
    // Speech windows end at 1.25 s; silent windows from 1 s to 4 s.
    let pause = firstPause(confidences: [0.9, 0.9, 0.9, 0.9] + Array(repeating: 0.1, count: 11))

    #expect(pause == 16_000 ..< 64_000)
  }

  @Test func ignoresSilenceShorterThanThreeSeconds() {
    #expect(firstPause(confidences: [0.9, 0.9] + Array(repeating: 0.1, count: 10) + [0.9]) == nil)
  }

  @Test func ignoresSilenceWithoutSpeechBefore() {
    #expect(firstPause(confidences: Array(repeating: 0.1, count: 20)) == nil)
    #expect(firstPause(confidences: Array(repeating: 0.5, count: 4) + Array(repeating: 0.1, count: 20)) == nil)
  }

  @Test func ambiguousWindowsBreakTheSilence() {
    let confidences = [0.9, 0.9] + Array(repeating: 0.1, count: 6) + [0.5] + Array(repeating: 0.1, count: 12)

    #expect(firstPause(confidences: confidences) == nil)
  }

  @Test func ignoresSilentWindowsAsLoudAsTheSpeech() {
    let confidences = [0.9, 0.9] + Array(repeating: 0.1, count: 14)

    #expect(firstPause(confidences: confidences, energies: Array(repeating: Self.speechEnergy, count: 16)) == nil)
  }

  @Test func unknownEnergyBreaksTheSilence() {
    var tracker = PauseTracker()
    _ = tracker.pause(after: SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.9), energy: Self.speechEnergy)
    _ = tracker.pause(after: SpeechWindow(samples: 4_000 ..< 12_000, speechConfidence: 0.1), energy: Self.quietEnergy)

    _ = tracker.pause(after: SpeechWindow(samples: 8_000 ..< 16_000, speechConfidence: 0.1), energy: nil)

    #expect(tracker.silence == nil)
  }
}
