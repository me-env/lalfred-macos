/// Decides which microphone to rebuild the capture on after each disruption of one dictation, and
/// when to give up.
nonisolated struct CaptureRecoveryBudget: Sendable {
  /// A device that keeps changing or failing must not reopen the microphone forever.
  static let maxRebuilds = 5
  /// A failing microphone gets one more try before it is excluded.
  private static let maxFailuresPerMicrophone = 2

  private(set) var excludedUIDs: Set<String> = []
  private var failuresByUID: [String: Int] = [:]
  private var rebuilds = 0

  /// The microphone to capture from next, or nil to give up. `select` picks a microphone among those
  /// not excluded.
  mutating func nextMicrophone(
    after disruption: CaptureDisruption,
    on active: InputDevice,
    select: (Set<String>) -> InputDevice?
  ) -> InputDevice? {
    guard rebuilds < Self.maxRebuilds else { return nil }
    rebuilds += 1
    recordFailure(disruption, of: active.uid)
    guard excludedUIDs.contains(active.uid) else { return active }
    return select(excludedUIDs)
  }

  private mutating func recordFailure(_ disruption: CaptureDisruption, of uid: String) {
    switch disruption {
    case .formatChanged:
      return
    case .deviceLost:
      excludedUIDs.insert(uid)
    case .startTimedOut, .stalled, .silent:
      let failures = failuresByUID[uid, default: 0] + 1
      failuresByUID[uid] = failures
      if failures >= Self.maxFailuresPerMicrophone {
        excludedUIDs.insert(uid)
      }
    }
  }
}
