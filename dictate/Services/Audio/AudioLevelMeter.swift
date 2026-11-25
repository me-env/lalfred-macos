import Foundation

/// Turns captured samples into levels for the indicator. Devices deliver about 90 buffers a second;
/// the indicator needs 30 levels a second.
nonisolated struct AudioLevelMeter {
  private static let reportIntervalNanoseconds: UInt64 = 1_000_000_000 / 30

  private var normalizer = SpeechLevelNormalizer()
  private var loudestDecibelsSinceReport = SpeechLevelNormalizer.silenceDecibels
  private var lastReportUptime: UInt64 = 0

  /// The loudest level since the last report, so short peaks still move the meter; nil between reports.
  mutating func levelToReport(for samples: UnsafeBufferPointer<Int16>) -> Float? {
    loudestDecibelsSinceReport = max(loudestDecibelsSinceReport, Self.decibels(of: samples))
    let now = DispatchTime.now().uptimeNanoseconds
    let elapsedNanoseconds = now - lastReportUptime
    guard elapsedNanoseconds >= Self.reportIntervalNanoseconds else { return nil }
    lastReportUptime = now
    defer { loudestDecibelsSinceReport = SpeechLevelNormalizer.silenceDecibels }
    return normalizer.level(for: loudestDecibelsSinceReport, elapsedSeconds: Float(elapsedNanoseconds) / 1_000_000_000)
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
