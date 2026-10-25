import Foundation

/// Turns captured samples into levels for the indicator. Devices deliver about 90 buffers a second;
/// the indicator needs 30 levels a second.
nonisolated struct AudioLevelMeter {
  private static let reportIntervalNanoseconds: UInt64 = 1_000_000_000 / 30
  private static let minimumDecibels: Float = -50

  private var loudestLevelSinceReport: Float = 0
  private var lastReportUptime: UInt64 = 0

  /// The loudest level since the last report, so short peaks still move the meter; nil between reports.
  mutating func levelToReport(for samples: UnsafeBufferPointer<Int16>) -> Float? {
    loudestLevelSinceReport = max(loudestLevelSinceReport, Self.normalizedLevel(of: samples))
    let now = DispatchTime.now().uptimeNanoseconds
    guard now - lastReportUptime >= Self.reportIntervalNanoseconds else { return nil }
    lastReportUptime = now
    defer { loudestLevelSinceReport = 0 }
    return loudestLevelSinceReport
  }

  /// 0 at -50 dBFS or below, 1 at full scale.
  private static func normalizedLevel(of samples: UnsafeBufferPointer<Int16>) -> Float {
    guard !samples.isEmpty else { return 0 }

    var sumOfSquares: Float = 0
    for sample in samples {
      let value = Float(sample) / Float(Int16.max)
      sumOfSquares += value * value
    }
    let rms = (sumOfSquares / Float(samples.count)).squareRoot()
    let averagePower = 20 * log10(max(rms, 1e-7))

    if averagePower <= minimumDecibels { return 0 }
    if averagePower >= 0 { return 1 }
    return (averagePower - minimumDecibels) / -minimumDecibels
  }
}
