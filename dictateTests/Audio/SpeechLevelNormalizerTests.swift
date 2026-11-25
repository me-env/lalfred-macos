import Testing
@testable import L_Alfred

struct SpeechLevelNormalizerTests {
  private static let reportSeconds: Float = 1.0 / 30
  private static let reportsPerSecond = 30

  /// Feeds `seconds` of reports cycling through `pattern`, returning every level.
  @discardableResult
  private func feed(_ normalizer: inout SpeechLevelNormalizer, _ pattern: [Float], seconds: Float) -> [Float] {
    let count = Int(seconds * Float(Self.reportsPerSecond))
    return (0..<count).map { index in
      normalizer.level(for: pattern[index % pattern.count], elapsedSeconds: Self.reportSeconds)
    }
  }

  /// Noise with a little jitter around `decibels`.
  private func noise(around decibels: Float) -> [Float] {
    [decibels, decibels + 2, decibels - 1, decibels + 1, decibels - 2]
  }

  /// Syllables at `loudest` with softer sounds and short gaps down to `noiseDecibels`.
  private func speech(loudest: Float, noiseDecibels: Float) -> [Float] {
    [loudest - 6, loudest, loudest - 3, loudest - 10, noiseDecibels + 2, loudest - 4, loudest - 1, noiseDecibels]
  }

  private func loudestSyllableLevel(after normalizer: inout SpeechLevelNormalizer, loudest: Float) -> Float {
    normalizer.level(for: loudest, elapsedSeconds: Self.reportSeconds)
  }

  @Test func quietMicSpeechFillsTheRange() {
    var normalizer = SpeechLevelNormalizer()
    feed(&normalizer, noise(around: -62), seconds: 1)
    let levels = feed(&normalizer, speech(loudest: -38, noiseDecibels: -62), seconds: 2)
    #expect(levels.suffix(30).max()! > 0.9)
    #expect(loudestSyllableLevel(after: &normalizer, loudest: -38) > 0.9)
  }

  @Test func loudMicSpeechFillsTheRange() {
    var normalizer = SpeechLevelNormalizer()
    feed(&normalizer, noise(around: -45), seconds: 1)
    feed(&normalizer, speech(loudest: -18, noiseDecibels: -45), seconds: 2)
    #expect(loudestSyllableLevel(after: &normalizer, loudest: -18) > 0.9)
  }

  @Test func softSyllablesStillMoveTheBarsClearly() {
    var normalizer = SpeechLevelNormalizer()
    feed(&normalizer, noise(around: -62), seconds: 1)
    feed(&normalizer, speech(loudest: -38, noiseDecibels: -62), seconds: 2)
    #expect(normalizer.level(for: -44, elapsedSeconds: Self.reportSeconds) > 0.5)
  }

  @Test func quietRoomStaysFlat() {
    var normalizer = SpeechLevelNormalizer()
    let levels = feed(&normalizer, noise(around: -60), seconds: 5)
    #expect(levels.allSatisfy { $0 < 0.05 })
  }

  @Test func noisyRoomStaysFlatOnceTheFloorAdapts() {
    var normalizer = SpeechLevelNormalizer()
    feed(&normalizer, noise(around: -70), seconds: 1)
    feed(&normalizer, noise(around: -45), seconds: 10)
    let levels = feed(&normalizer, noise(around: -45), seconds: 3)
    #expect(levels.allSatisfy { $0 < 0.1 })
  }

  @Test func digitalSilenceStaysAtZero() {
    var normalizer = SpeechLevelNormalizer()
    let levels = feed(&normalizer, [-140], seconds: 2)
    #expect(levels.allSatisfy { $0 == 0 })
  }

  @Test func peakDecaysAfterALoudBurst() {
    var normalizer = SpeechLevelNormalizer()
    feed(&normalizer, noise(around: -60), seconds: 1)
    feed(&normalizer, speech(loudest: -32, noiseDecibels: -60), seconds: 2)
    feed(&normalizer, [-5], seconds: 0.2)
    let rightAfterBurst = loudestSyllableLevel(after: &normalizer, loudest: -32)
    feed(&normalizer, speech(loudest: -32, noiseDecibels: -60), seconds: 5)
    #expect(rightAfterBurst < 0.7)
    #expect(loudestSyllableLevel(after: &normalizer, loudest: -32) > 0.9)
  }

  @Test func invalidInputsStayInRange() {
    var normalizer = SpeechLevelNormalizer()
    let inputs: [Float] = [.nan, -.infinity, .infinity, 12, -30, .nan, -200, 0]
    let elapsedValues: [Float] = [.nan, 0, -1, .infinity, 1000, Self.reportSeconds]
    let levels = inputs.flatMap { decibels in
      elapsedValues.map { normalizer.level(for: decibels, elapsedSeconds: $0) }
    }
    #expect(levels.allSatisfy { !$0.isNaN && $0 >= 0 && $0 <= 1 })
  }
}
