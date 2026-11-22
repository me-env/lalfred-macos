import Foundation

/// What the current capture has delivered so far, in seconds on one clock.
nonisolated struct CaptureActivity: Equatable, Sendable {
  var startTime: TimeInterval
  var lastCallbackTime: TimeInterval?
  /// Start of the current run of buffers holding only exact zeros, if the last buffer was one.
  var zeroRunStartTime: TimeInterval?
  var hasDeliveredSound = false
}

/// Spots a capture that is running without delivering audio, which CoreAudio does not report.
nonisolated enum CaptureWatchdog {
  /// Bluetooth headsets deliver their first callback within about 1–2 s.
  static let startTimeout: TimeInterval = 3
  static let stallTimeout: TimeInterval = 2
  /// Only for the Mac's internal mic: headsets' noise gates send exact zeros while the user is quiet.
  static let silenceTimeout: TimeInterval = 3

  static func verdict(for activity: CaptureActivity, at now: TimeInterval, isInternalMic: Bool) -> CaptureDisruption? {
    guard let lastCallbackTime = activity.lastCallbackTime else {
      return now - activity.startTime >= startTimeout ? .startTimedOut : nil
    }
    if now - lastCallbackTime >= stallTimeout {
      return .stalled
    }
    guard isInternalMic, activity.hasDeliveredSound, let zeroRunStartTime = activity.zeroRunStartTime else { return nil }
    return now - zeroRunStartTime >= silenceTimeout ? .silent : nil
  }
}
