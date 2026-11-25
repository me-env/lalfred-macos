import Foundation


/// A stretch of the recording and how likely it holds speech. Positions are sample indexes from the
/// start of the recording.
nonisolated struct SpeechWindow: Equatable, Sendable {
  let samples: Range<Int>
  /// From 0 (no speech) to 1 (speech).
  let speechConfidence: Double
}

/// Classifies audio fed in recording order. A window comes back once all of its audio has been fed,
/// in increasing order of start.
nonisolated protocol VoiceActivityDetecting: AnyObject {
  /// `chunk` is 16 kHz mono s16le PCM whose first sample is at `position`.
  func analyze(_ chunk: Data, startingAt position: Int) -> [SpeechWindow]
}
