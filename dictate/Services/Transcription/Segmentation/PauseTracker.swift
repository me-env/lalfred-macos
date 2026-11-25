import Foundation


/// Follows classified windows in recording order and reports a clear pause: confident speech, then
/// at least `minimumPauseDuration` of windows confidently without speech and much quieter than that
/// speech. An ambiguous window breaks the silence; when in doubt, there is no pause.
nonisolated struct PauseTracker {
  /// Long enough to be the user stopping to think, not the gap between two sentences.
  static let minimumPauseDuration = 3
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
  static let minimumPauseSamples = minimumPauseDuration * TranscriptionAudio.sampleRate

  private var latestSpeech: (end: Int, energy: Double)?
  /// The confidently silent stretch after the latest speech, nil outside one.
  private(set) var silence: Range<Int>?

  /// The pause once `window` makes the silence long enough. `energy` is the window's mean energy,
  /// nil when unknown, which makes the window ambiguous.
  mutating func pause(after window: SpeechWindow, energy: Double?) -> Range<Int>? {
    guard let energy else {
      silence = nil
      return nil
    }
    if window.speechConfidence >= Self.speechConfidence {
      latestSpeech = (end: window.samples.upperBound, energy: energy)
      silence = nil
      return nil
    }
    silence = extendedSilence(with: window, energy: energy)
    guard let silence, silence.count >= Self.minimumPauseSamples else { return nil }
    return silence
  }

  /// The silence including `window`, nil if `window` isn't clearly silent or the silence doesn't
  /// follow speech closely.
  private func extendedSilence(with window: SpeechWindow, energy: Double) -> Range<Int>? {
    guard let latestSpeech, isClearlySilent(window, energy: energy, speechEnergy: latestSpeech.energy) else { return nil }
    if let silence { return silence.lowerBound ..< window.samples.upperBound }
    guard window.samples.lowerBound <= latestSpeech.end + Self.maximumFadeOutSamples else { return nil }
    return window.samples
  }

  private func isClearlySilent(_ window: SpeechWindow, energy: Double, speechEnergy: Double) -> Bool {
    window.speechConfidence < Self.silenceConfidence
      && energy <= speechEnergy * Self.maximumSilenceToSpeechEnergyRatio
  }
}
