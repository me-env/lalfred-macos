import Foundation
import os
@testable import L_Alfred

/// A recording described by its pauses; every other sample is speech.
struct TestRecording {
  static let rate = TranscriptionAudio.sampleRate

  let duration: Double
  /// Pauses as ranges of seconds.
  let pauses: [Range<Double>]

  var sampleCount: Int { Int(duration * Double(Self.rate)) }

  var pauseSamples: [Range<Int>] {
    pauses.map { Int($0.lowerBound * Double(Self.rate)) ..< Int($0.upperBound * Double(Self.rate)) }
  }

  func hasSpeech(in range: Range<Int>) -> Bool {
    !pauseSamples.contains { $0.contains(range.lowerBound) && range.upperBound <= $0.upperBound }
  }

  /// Loud square wave for speech, faint noise in pauses.
  var pcm: Data {
    let pauses = pauseSamples
    var samples = [Int16](repeating: 0, count: sampleCount)
    for index in samples.indices {
      let isPause = pauses.contains { $0.contains(index) }
      samples[index] = isPause ? Int16(index % 7) - 3 : (index % 40 < 20 ? 8_000 : -8_000)
    }
    return samples.withUnsafeBytes { Data($0) }
  }
}

/// Classifies like the SoundAnalysis detector: 0.5 s windows every 0.25 s from the first sample fed,
/// each returned once all of its audio arrived. Speech comes from the recording's description.
final class FakeVoiceActivityDetector: VoiceActivityDetecting {
  static let windowLength = 8_000
  static let hop = 4_000

  private let recording: TestRecording
  private var origin: Int?
  private var fedEnd = 0
  private var nextWindowStart = 0
  private(set) var firstPositionFed: Int?

  init(recording: TestRecording) {
    self.recording = recording
  }

  func analyze(_ chunk: Data, startingAt position: Int) -> [SpeechWindow] {
    if origin == nil {
      origin = position
      firstPositionFed = position
      nextWindowStart = position
    }
    fedEnd = position + chunk.count / 2
    var windows: [SpeechWindow] = []
    while nextWindowStart + Self.windowLength <= fedEnd {
      let range = nextWindowStart ..< nextWindowStart + Self.windowLength
      windows.append(SpeechWindow(samples: range, speechConfidence: recording.hasSpeech(in: range) ? 0.9 : 0.1))
      nextWindowStart += Self.hop
    }
    return windows
  }
}

/// Makes fake detectors and remembers them.
final class FakeDetectorFactory: @unchecked Sendable {
  private let recording: TestRecording
  private let detectors = OSAllocatedUnfairLock(initialState: [FakeVoiceActivityDetector]())

  init(recording: TestRecording) {
    self.recording = recording
  }

  var created: [FakeVoiceActivityDetector] {
    detectors.withLock { $0 }
  }

  func make() -> VoiceActivityDetecting? {
    let detector = FakeVoiceActivityDetector(recording: recording)
    detectors.withLock { $0.append(detector) }
    return detector
  }
}

/// Splits `data` into chunks of varying even sizes, like capture buffers.
func chunked(_ data: Data, sizes: [Int]) -> [Data] {
  var chunks: [Data] = []
  var offset = 0
  var sizeIndex = 0
  while offset < data.count {
    let size = min(sizes[sizeIndex % sizes.count], data.count - offset)
    chunks.append(data.subdata(in: offset ..< offset + size))
    offset += size
    sizeIndex += 1
  }
  return chunks
}

/// The segments `actions` describe, as their audio.
func segments(of actions: [AudioSegmenter.Action]) -> [Data] {
  actions.reduce(into: [Data()]) { segments, action in
    switch action {
    case .audio(let chunk):
      segments[segments.count - 1].append(chunk)
    case .cut:
      segments.append(Data())
    }
  }
}

func seconds(_ samples: Int) -> Double {
  Double(samples) / Double(TestRecording.rate)
}
