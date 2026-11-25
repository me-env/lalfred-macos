import Foundation
import Testing
@testable import L_Alfred

struct VoiceBandLevelsTests {
  private static let sampleRate: Float = 16_000
  /// 20 ms, a headset's buffer.
  private static let chunkLength = 320
  private static let chunkNanoseconds: UInt64 = 20_000_000
  private static let lowBands = [0, 1]
  private static let highBands = [4, 5]

  /// Deterministic white noise in -1...1.
  private struct Noise {
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15

    mutating func next() -> Float {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Float(Int64(bitPattern: state) >> 40) / Float(1 << 23)
    }
  }

  /// Sines and white noise, amplitudes in dBFS.
  private struct Sound {
    var tones: [(hertz: Float, decibels: Float)] = []
    var noiseDecibels: Float?

    static let silence = Sound()
    static func noise(_ decibels: Float) -> Sound { Sound(noiseDecibels: decibels) }
    static func tone(_ hertz: Float, _ decibels: Float, noise: Float?) -> Sound {
      Sound(tones: [(hertz, decibels)], noiseDecibels: noise)
    }

    func sample(at index: Int, noise: inout Noise) -> Float {
      let time = Float(index) / VoiceBandLevelsTests.sampleRate
      let toneSum = tones.reduce(Float(0)) { sum, tone in
        sum + amplitude(tone.decibels) * sin(2 * .pi * tone.hertz * time)
      }
      let noiseValue = noise.next() * (noiseDecibels.map(amplitude) ?? 0)
      return toneSum + noiseValue
    }

    private func amplitude(_ decibels: Float) -> Float {
      pow(10, decibels / 20)
    }
  }

  /// Feeds an `AudioLevelMeter` chunk by chunk on a simulated clock.
  private struct MeterDriver {
    private var meter = AudioLevelMeter()
    private var uptime: UInt64 = 1_000_000_000
    private var sampleIndex = 0
    private var noise = Noise()

    @discardableResult
    mutating func feed(_ sound: Sound, seconds: Float) -> [ListeningLevels] {
      let chunkCount = Int(seconds * VoiceBandLevelsTests.sampleRate) / VoiceBandLevelsTests.chunkLength
      return (0..<chunkCount).compactMap { _ in feedChunk(of: sound) }
    }

    private mutating func feedChunk(of sound: Sound) -> ListeningLevels? {
      let chunk = (0..<VoiceBandLevelsTests.chunkLength).map { offset in
        Self.int16(sound.sample(at: sampleIndex + offset, noise: &noise))
      }
      sampleIndex += chunk.count
      uptime += VoiceBandLevelsTests.chunkNanoseconds
      return chunk.withUnsafeBufferPointer { meter.levelsToReport(for: $0, uptimeNanoseconds: uptime) }
    }

    private static func int16(_ value: Float) -> Int16 {
      Int16((min(max(value, -1), 1) * Float(Int16.max)).rounded())
    }
  }

  private func meanLevel(of bands: [Int], in reports: [ListeningLevels]) -> Float {
    let total = reports.reduce(Float(0)) { sum, levels in
      sum + bands.reduce(Float(0)) { $0 + levels[$1] }
    }
    return total / Float(reports.count * bands.count)
  }

  private func steadyReports(of sound: Sound, roomNoise: Float) -> [ListeningLevels] {
    var driver = MeterDriver()
    driver.feed(.noise(roomNoise), seconds: 1)
    driver.feed(sound, seconds: 1)
    return driver.feed(sound, seconds: 1)
  }

  @Test func lowToneLightsTheLowBars() {
    let reports = steadyReports(of: .tone(200, -20, noise: -70), roomNoise: -70)
    #expect(meanLevel(of: Self.lowBands, in: reports) > 0.6)
    #expect(meanLevel(of: Self.highBands, in: reports) < 0.1)
  }

  @Test func highToneLightsTheHighBars() {
    let reports = steadyReports(of: .tone(4_500, -20, noise: -70), roomNoise: -70)
    #expect(meanLevel(of: Self.highBands, in: reports) > 0.4)
    #expect(meanLevel(of: Self.lowBands, in: reports) < 0.1)
  }

  @Test func silenceKeepsEveryBarAtRest() {
    var driver = MeterDriver()
    let reports = driver.feed(.silence, seconds: 3)
    #expect(!reports.isEmpty)
    #expect(reports.allSatisfy { $0 == .silent })
  }

  @Test func roomNoiseKeepsEveryBarAtRest() {
    for noiseDecibels: Float in [-70, -55, -40] {
      var driver = MeterDriver()
      let reports = driver.feed(.noise(noiseDecibels), seconds: 5)
      #expect(reports.allSatisfy { $0 == .silent }, "noise at \(noiseDecibels) dBFS")
    }
  }

  @Test func quietAndLoudMicsLightTheSameBars() {
    let quiet = alternatingToneReports(loudness: -40)
    let loud = alternatingToneReports(loudness: -15)
    for band in 0..<ListeningLevels.bandCount {
      let difference = abs(meanLevel(of: [band], in: quiet) - meanLevel(of: [band], in: loud))
      #expect(difference < 0.15, "band \(band)")
    }
  }

  /// Like vowels and fricatives: a low tone then a high one, the room noise 40 dB below.
  private func alternatingToneReports(loudness: Float) -> [ListeningLevels] {
    let noise = loudness - 40
    var driver = MeterDriver()
    driver.feed(.noise(noise), seconds: 1)
    var reports: [ListeningLevels] = []
    for _ in 0..<8 {
      reports += driver.feed(.tone(250, loudness, noise: noise), seconds: 0.2)
      reports += driver.feed(.tone(4_000, loudness, noise: noise), seconds: 0.2)
    }
    return Array(reports.suffix(40))
  }

  @Test func extremeInputStaysFiniteAndInRange() {
    var driver = MeterDriver()
    var reports = driver.feed(.noise(0), seconds: 1)
    reports += driver.feed(.silence, seconds: 1)
    reports += driver.feed(Sound(tones: [(300, 6), (5_000, 6)], noiseDecibels: 0), seconds: 1)
    reports += driver.feed(.tone(100, -90, noise: -100), seconds: 1)
    for levels in reports {
      for band in 0..<ListeningLevels.bandCount {
        #expect((0...1).contains(levels[band]))
      }
    }
  }

  @Test func levelsAreClampedAndNaNReadsAsZero() {
    let levels = ListeningLevels(clamping: [.nan, -1, 2, 0.5, .infinity, -.infinity, 7, 7])
    #expect(levels == ListeningLevels(clamping: [0, 0, 1, 0.5, 1, 0, 0, 0]))
  }

  @Test func toneReadsAtItsRMSInItsBand() {
    let analyzer = VoiceSpectrumAnalyzer()
    var noise = Noise()
    let sound = Sound.tone(1_000, -20, noise: nil)
    let samples = (0..<VoiceSpectrumAnalyzer.frameLength).map { index in
      Int16((sound.sample(at: index, noise: &noise) * Float(Int16.max)).rounded())
    }
    samples.withUnsafeBufferPointer { analyzer.append($0) }
    let decibels = analyzer.bandDecibels()
    #expect(abs(decibels[3] - -23) < 1)
    #expect(decibels[0] < -60)
    #expect(decibels[5] < -60)
  }

  @Test func analysisCostsLittleCPU() {
    let analyzer = VoiceSpectrumAnalyzer()
    let chunk = [Int16](repeating: 1_000, count: Self.chunkLength)
    let reportCount = 3_000
    let duration = ContinuousClock().measure {
      for _ in 0..<reportCount {
        chunk.withUnsafeBufferPointer { samples in
          for _ in 0..<3 { analyzer.append(samples) }
        }
        _ = analyzer.bandDecibels()
      }
    }
    let microsecondsPerReport = Double(duration.components.attoseconds) / 1e12 / Double(reportCount)
      + Double(duration.components.seconds) * 1e6 / Double(reportCount)
    #expect(microsecondsPerReport < 100, "\(microsecondsPerReport) µs per report")
  }
}
