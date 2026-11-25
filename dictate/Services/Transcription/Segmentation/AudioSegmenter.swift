import Foundation


/// Splits a recording into segments cut at pauses, at least `minimumSegmentDuration` long.
/// Audio passes straight through until then; after it, audio is held back until the detector has
/// classified it, so a cut can still land in it.
nonisolated struct AudioSegmenter {
  enum Action: Equatable {
    /// Audio for the current segment.
    case audio(Data)
    /// The current segment is complete; the following audio starts a new one.
    case cut
  }

  static let minimumSegmentDuration = 20
  private static let minimumSegmentSamples = minimumSegmentDuration * TranscriptionAudio.sampleRate
  private static let bytesPerSample = MemoryLayout<Int16>.size

  /// Nil when no detector can be created; the recording is then never cut.
  private let makeDetector: () -> VoiceActivityDetecting?
  private var detector: VoiceActivityDetecting?
  private var isDetectorUnavailable = false
  private var segmentStart = 0
  /// End of the audio sent to the current segment.
  private var sentEnd = 0
  /// End of the audio the detector has seen.
  private var analyzedEnd = 0
  /// Audio received but not sent yet, from `sentEnd` on.
  private var heldBack = Data()

  init(makeDetector: @escaping () -> VoiceActivityDetecting?) {
    self.makeDetector = makeDetector
  }

  private var receivedEnd: Int { sentEnd + heldBack.count / Self.bytesPerSample }
  private var searchStart: Int { segmentStart + Self.minimumSegmentSamples }

  mutating func append(_ chunk: Data) -> [Action] {
    heldBack.append(chunk)
    var actions: [Action] = []
    while true {
      actions += send(upTo: searchStart)
      guard receivedEnd > searchStart, let detector = activeDetector() else {
        if isDetectorUnavailable { actions += send(upTo: receivedEnd) }
        return actions
      }

      let windows = analyzeUnseenAudio(with: detector)
      guard let cut = PauseCutPoint.find(in: windows, audio: heldBack, audioStart: sentEnd) else {
        // Audio before the latest window's start can't be in a window still to come.
        actions += send(upTo: windows.last?.samples.lowerBound ?? sentEnd)
        return actions
      }
      actions += send(upTo: cut)
      actions.append(.cut)
      startSegment(at: cut)
    }
  }

  /// Sends what is held back: the recording ended.
  mutating func finish() -> [Action] {
    guard !heldBack.isEmpty else { return [] }
    defer { heldBack = Data() }
    return [.audio(heldBack)]
  }

  private mutating func activeDetector() -> VoiceActivityDetecting? {
    if let detector { return detector }
    guard !isDetectorUnavailable else { return nil }
    detector = makeDetector()
    isDetectorUnavailable = detector == nil
    analyzedEnd = searchStart
    return detector
  }

  private mutating func analyzeUnseenAudio(with detector: VoiceActivityDetecting) -> [SpeechWindow] {
    let unseen = heldBack.subdata(in: byteOffset(of: analyzedEnd) ..< byteOffset(of: receivedEnd))
    let windows = detector.analyze(unseen, startingAt: analyzedEnd)
    analyzedEnd = receivedEnd
    return windows
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

  private mutating func startSegment(at position: Int) {
    segmentStart = position
    detector = nil
  }

  /// Offset in `heldBack` of the sample at recording `position`.
  private func byteOffset(of position: Int) -> Int {
    (position - sentEnd) * Self.bytesPerSample
  }
}
