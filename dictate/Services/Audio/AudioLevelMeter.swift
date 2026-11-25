import Foundation

/// Turns captured samples into levels for the indicator. Devices deliver about 90 buffers a second;
/// the indicator needs 30 levels a second.
nonisolated struct AudioLevelMeter {
  private static let reportIntervalNanoseconds: UInt64 = 1_000_000_000 / 30

  /// Gates every band: when the whole signal reads as silence or noise, all bars rest.
  private var overallNormalizer = SpeechLevelNormalizer()
  /// Each band against its own recent range, so the bars move apart.
  private var bandNormalizers = Array(repeating: SpeechLevelNormalizer(), count: ListeningLevels.bandCount)
  private let spectrum = VoiceSpectrumAnalyzer()
  private var loudestDecibelsSinceReport = SpeechLevelNormalizer.silenceDecibels
  private var lastReportUptime: UInt64 = 0

  /// The gate uses the loudest level since the last report, so short peaks still open it; the bands
  /// use the latest frame. Nil between reports.
  mutating func levelsToReport(
    for samples: UnsafeBufferPointer<Int16>,
    uptimeNanoseconds now: UInt64 = DispatchTime.now().uptimeNanoseconds
  ) -> ListeningLevels? {
    loudestDecibelsSinceReport = max(loudestDecibelsSinceReport, Self.decibels(of: samples))
    spectrum.append(samples)
    let elapsedNanoseconds = now &- lastReportUptime
    guard elapsedNanoseconds >= Self.reportIntervalNanoseconds else { return nil }
    lastReportUptime = now
    defer { loudestDecibelsSinceReport = SpeechLevelNormalizer.silenceDecibels }

    let elapsedSeconds = Float(elapsedNanoseconds) / 1_000_000_000
    let overallLevel = overallNormalizer.level(for: loudestDecibelsSinceReport, elapsedSeconds: elapsedSeconds)
    // Analyzed even in silence, so each band's noise floor stays current.
    let bandLevels = updatedBandLevels(elapsedSeconds: elapsedSeconds)
    guard overallLevel > 0 else { return .silent }
    return ListeningLevels(clamping: bandLevels)
  }

  private mutating func updatedBandLevels(elapsedSeconds: Float) -> SIMD8<Float> {
    let decibels = spectrum.bandDecibels()
    var levels = SIMD8<Float>.zero
    for band in 0..<ListeningLevels.bandCount {
      levels[band] = bandNormalizers[band].level(for: decibels[band], elapsedSeconds: elapsedSeconds)
    }
    return levels
  }

  /// RMS power in dBFS.
  private static func decibels(of samples: UnsafeBufferPointer<Int16>) -> Float {
    guard !samples.isEmpty else { return SpeechLevelNormalizer.silenceDecibels }

    var sumOfSquares: Float = 0
    for sample in samples {
      let value = Float(sample) / Float(Int16.max)
      sumOfSquares += value * value
    }
    let rms = (sumOfSquares / Float(samples.count)).squareRoot()
    return 20 * log10(max(rms, 1e-7))
  }
}
