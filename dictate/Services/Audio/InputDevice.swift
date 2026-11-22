import CoreAudio

/// An input device as seen at one moment, with what microphone selection and recovery need.
nonisolated struct InputDevice: Equatable, Sendable {
  enum Transport: Equatable, Sendable {
    case builtIn
    case bluetooth
    /// Loopback and aggregate devices, which carry other apps' audio rather than a microphone.
    case virtual
    case other
  }

  let id: AudioDeviceID
  /// Stable across reconnections, unlike `id`.
  let uid: String
  let name: String
  let transport: Transport
  /// The Mac's own microphone, as opposed to a built-in input such as the headphone jack.
  let isInternalMic: Bool
  let isAlive: Bool
}
