import Foundation


/// Follows classified windows in recording order and reports a clear pause in the current segment:
/// confident speech, then windows confidently without speech and much quieter than that speech,
/// lasting `longPauseDuration`, or `shortPauseDuration` once the segment is `minimumSegmentDuration`
/// long. An ambiguous window breaks the silence; when in doubt, there is no pause.
nonisolated struct PauseTracker {
  /// The user stopping to think, not the gap between two sentences; cuts a long enough segment.
  static let shortPauseDuration = 3
  /// Long enough to cut a segment of any length.
  static let longPauseDuration = 5
  /// A short pause cuts only from this segment length on.
  static let minimumSegmentDuration = 20
  /// From this confidence on, a window holds speech.
  static let speechConfidence = 0.7
  /// Below this confidence, a window holds no speech. Silence measured 0.17–0.36.
  static let silenceConfidence = 0.4
  /// A silent window is at least 10 dB quieter than the latest speech, or it may be speech the
  /// classifier missed.
  static let maximumSilenceToSpeechEnergyRatio = 0.1
  /// How soon after the latest speech window the silence must start; the windows between are the
  /// speech fading out.
  static let maximumFadeOutSamples = TranscriptionAudio.sampleRate
  static let shortPauseSamples = shortPauseDuration * TranscriptionAudio.sampleRate
  static let longPauseSamples = longPauseDuration * TranscriptionAudio.sampleRate
  static let minimumSegmentSamples = minimumSegmentDuration * TranscriptionAudio.sampleRate

  private var segmentStart = 0
  /// End of the latest confident speech window in the current segment.
  private var latestSpeechEnd: Int?
  /// Mean energy of the latest confident speech window, in any segment: silence is judged by it.
  private var latestSpeechEnergy: Double?
  /// The confidently silent stretch after the current segment's latest speech, nil outside one.
  private(set) var silence: Range<Int>?

  /// Where the cut may go, once `window` makes the silence a pause. `energy` is the window's mean
  /// energy, nil when unknown, which makes the window ambiguous.
  mutating func pause(after window: SpeechWindow, energy: Double?) -> Range<Int>? {
    guard let energy else {
      silence = nil
      return nil
    }
    if window.speechConfidence >= Self.speechConfidence {
      latestSpeechEnd = window.samples.upperBound
      latestSpeechEnergy = energy
      silence = nil
      return nil
    }
    silence = extendedSilence(with: window, energy: energy)
    return silence.flatMap(cutRange(in:))
  }

  /// Confidently without speech and much quieter than the latest speech; false before any speech.
  func isClearlySilent(_ window: SpeechWindow, energy: Double?) -> Bool {
    guard let energy, let latestSpeechEnergy else { return false }
    return window.speechConfidence < Self.silenceConfidence
      && energy <= latestSpeechEnergy * Self.maximumSilenceToSpeechEnergyRatio
  }

  /// The next pause needs speech after `position`.
  mutating func startSegment(at position: Int) {
    segmentStart = position
    latestSpeechEnd = nil
    silence = nil
  }

  /// The silence including `window`, nil if `window` isn't clearly silent or the silence doesn't
  /// follow the segment's speech closely.
  private func extendedSilence(with window: SpeechWindow, energy: Double) -> Range<Int>? {
    guard let latestSpeechEnd, isClearlySilent(window, energy: energy) else { return nil }
    if let silence { return silence.lowerBound ..< window.samples.upperBound }
    guard window.samples.lowerBound <= latestSpeechEnd + Self.maximumFadeOutSamples else { return nil }
    return window.samples
  }

  /// A long pause cuts anywhere in it; a short one only after the minimum segment length.
  private func cutRange(in silence: Range<Int>) -> Range<Int>? {
    if silence.count >= Self.longPauseSamples { return silence }
    let minimumSegmentEnd = segmentStart + Self.minimumSegmentSamples
    guard silence.count >= Self.shortPauseSamples, silence.upperBound > minimumSegmentEnd else { return nil }
    return max(silence.lowerBound, minimumSegmentEnd) ..< silence.upperBound
  }
}
