/// Why the capture of the active microphone has to be rebuilt.
nonisolated enum CaptureDisruption: Equatable, Sendable {
  /// The microphone disappeared or is no longer alive.
  case deviceLost
  /// Its sample rate or stream layout changed, e.g. a Bluetooth headset switching to call mode.
  case formatChanged
  /// No callback arrived after starting.
  case startTimedOut
  /// Callbacks stopped arriving.
  case stalled
  /// A built-in mic went from sound to exact zeros.
  case silent

  /// The disruption a device change caused to the active microphone, if any. A change of the system
  /// default input alone is none: the dictation keeps the microphone it started with.
  static func detect(activeUID: String, in devices: [InputDevice], formatMatches: Bool) -> CaptureDisruption? {
    guard let active = devices.first(where: { $0.uid == activeUID }), active.isAlive else {
      return .deviceLost
    }
    return formatMatches ? nil : .formatChanged
  }
}
