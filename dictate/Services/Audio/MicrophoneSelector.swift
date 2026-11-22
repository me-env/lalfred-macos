import CoreAudio

/// Picks the microphone a dictation records from.
nonisolated enum MicrophoneSelector {
  struct Context: Sendable {
    let devices: [InputDevice]
    let systemDefault: AudioDeviceID?
    let preferences: MicrophonePreferences
    let isLidClosed: Bool
    /// Microphones that already failed during this dictation.
    var excludedUIDs: Set<String> = []
  }

  static func select(in context: Context) -> InputDevice? {
    let candidates = usableDevices(in: context)
    guard context.preferences.mode == .priorityList,
          let preferred = firstPrioritized(context.preferences.priority, in: candidates) else {
      return selectFollowingSystemDefault(from: candidates, context: context)
    }
    return preferred
  }

  /// With the lid closed the internal mic records silence, so it is used only when nothing else is.
  private static func usableDevices(in context: Context) -> [InputDevice] {
    let alive = context.devices.filter { $0.isAlive && !context.excludedUIDs.contains($0.uid) }
    guard context.isLidClosed else { return alive }
    let external = alive.filter { !$0.isInternalMic }
    return external.isEmpty ? alive : external
  }

  private static func firstPrioritized(
    _ priority: [MicrophonePreferences.RememberedMicrophone],
    in candidates: [InputDevice]
  ) -> InputDevice? {
    priority.lazy.compactMap { remembered in candidates.first { $0.uid == remembered.uid } }.first
  }

  private static func selectFollowingSystemDefault(from candidates: [InputDevice], context: Context) -> InputDevice? {
    let builtIn = candidates.first { $0.transport == .builtIn }
    guard let systemDefault = candidates.first(where: { $0.id == context.systemDefault }) else {
      return builtIn ?? candidates.first { $0.transport != .virtual } ?? candidates.first
    }
    guard systemDefault.transport == .bluetooth, context.preferences.avoidBluetoothMicrophone, let builtIn else {
      return systemDefault
    }
    return builtIn
  }
}
