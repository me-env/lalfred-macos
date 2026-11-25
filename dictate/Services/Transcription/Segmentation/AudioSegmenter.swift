import Foundation


/// Splits a recording into segments cut in clear pauses (see `PauseTracker`). Audio is held back
/// until the detector has classified it and it can no longer be part of a pause, so a cut can still
/// land in it. After a cut, the new segment's audio is held until something other than clear silence
/// is heard; a segment ending the recording without any is dropped.
nonisolated struct AudioSegmenter {
  enum Action: Equatable {
    /// Audio for the current segment.
    case audio(Data)
    /// The current segment is complete; the following audio starts a new one.
    case cut
  }

  /// Audio at the end of the recording the detector hasn't classified yet, short enough to hold
  /// no word: a window is classified every 0.25 s.
  static let maximumUnclassifiedTailSamples = TranscriptionAudio.sampleRate / 2
  private static let bytesPerSample = MemoryLayout<Int16>.size

  /// Nil when no detector can be created; the recording is then never cut.
  private let makeDetector: () -> VoiceActivityDetecting?
  private var detector: VoiceActivityDetecting?
  private var isDetectorUnavailable = false
  private var pauseTracker = PauseTracker()
  private var segmentStart = 0
  /// False from a cut until the new segment holds something other than clear silence.
  private var hasSound = true
  /// End of the audio sent to the current segment.
  private var sentEnd = 0
  /// End of the audio the detector has seen.
  private var analyzedEnd = 0
  private var latestWindow: SpeechWindow?
  /// Audio received but not sent yet, from `sentEnd` on.
  private var heldBack = Data()

  init(makeDetector: @escaping () -> VoiceActivityDetecting?) {
    self.makeDetector = makeDetector
  }

  private var receivedEnd: Int { sentEnd + heldBack.count / Self.bytesPerSample }

  mutating func append(_ chunk: Data) -> [Action] {
    heldBack.append(chunk)
    guard let detector = activeDetector() else { return send(upTo: receivedEnd) }

    var actions: [Action] = []
    for window in analyzeUnseenAudio(with: detector) {
      actions += judge(window)
    }
    return actions + send(upTo: releasableEnd)
  }

  /// Sends what is held back, unless it is a silent segment after a cut: the recording ended.
  mutating func finish() -> [Action] {
    guard !isSilentTail else { return [] }
    return send(upTo: receivedEnd)
  }

  private mutating func activeDetector() -> VoiceActivityDetecting? {
    if let detector { return detector }
    guard !isDetectorUnavailable else { return nil }
    detector = makeDetector()
    isDetectorUnavailable = detector == nil
    return detector
  }

  private mutating func analyzeUnseenAudio(with detector: VoiceActivityDetecting) -> [SpeechWindow] {
    let unseenStart = analyzedEnd
    let unseen = heldBack.subdata(in: byteOffset(of: unseenStart) ..< byteOffset(of: receivedEnd))
    analyzedEnd = receivedEnd
    return detector.analyze(unseen, startingAt: unseenStart)
  }

  private mutating func judge(_ window: SpeechWindow) -> [Action] {
    latestWindow = window
    let energy = meanEnergy(of: window)
    hasSound = hasSound || !pauseTracker.isClearlySilent(window, energy: energy)
    guard let pause = pauseTracker.pause(after: window, energy: energy) else { return [] }
    return cut(in: pause)
  }

  /// Over the part of `window` still held back; after a cut, that is the part in the new segment.
  private func meanEnergy(of window: SpeechWindow) -> Double? {
    let heldPart = window.samples.clamped(to: sentEnd ..< receivedEnd)
    return PauseCutPoint.meanEnergy(of: heldPart, audio: heldBack, audioStart: sentEnd)
  }

  private mutating func cut(in pause: Range<Int>) -> [Action] {
    let position = PauseCutPoint.quietestFrameCenter(in: pause.clamped(to: sentEnd ..< receivedEnd), audio: heldBack, audioStart: sentEnd)
    let actions = send(upTo: position) + [.cut]
    segmentStart = position
    hasSound = false
    pauseTracker.startSegment(at: position)
    return actions
  }

  /// Nothing of a segment without sound yet. Otherwise, audio before the latest window's start
  /// can't be in a window still to come, nor audio before the silence that may become a pause.
  private var releasableEnd: Int {
    guard hasSound, let latestWindow else { return sentEnd }
    let classifiedStart = latestWindow.samples.lowerBound
    return min(classifiedStart, pauseTracker.silence?.lowerBound ?? classifiedStart)
  }

  /// After a cut, only clear silence was classified, and the rest is too short to hold a word.
  private var isSilentTail: Bool {
    let classifiedEnd = max(latestWindow?.samples.upperBound ?? segmentStart, segmentStart)
    return !hasSound && receivedEnd - classifiedEnd < Self.maximumUnclassifiedTailSamples
  }

  /// Sends the held-back audio before `position`, as far as it was received.
  private mutating func send(upTo position: Int) -> [Action] {
    let end = min(position, receivedEnd)
    guard end > sentEnd else { return [] }
    let splitOffset = byteOffset(of: end)
    let sent = heldBack.subdata(in: 0 ..< splitOffset)
    heldBack = heldBack.subdata(in: splitOffset ..< heldBack.count)
    sentEnd = end
    return [.audio(sent)]
  }

  /// Offset in `heldBack` of the sample at recording `position`.
  private func byteOffset(of position: Int) -> Int {
    (position - sentEnd) * Self.bytesPerSample
  }
}
