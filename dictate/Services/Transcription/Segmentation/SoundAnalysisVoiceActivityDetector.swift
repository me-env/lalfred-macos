import AVFoundation
import SoundAnalysis
import os


/// Detects speech with Apple's built-in sound classifier, a Core ML model shipped with macOS.
/// Costs about 5.5 ms of CPU per second of audio on Apple Silicon.
nonisolated final class SoundAnalysisVoiceActivityDetector: VoiceActivityDetecting {
  /// The shortest window the classifier accepts; with half overlap, a window starts every 0.25 s.
  private static let windowDuration = CMTime(value: 8_000, timescale: 16_000)
  private static let overlapFactor = 0.5
  private static let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Double(TranscriptionAudio.sampleRate),
    channels: 1,
    interleaved: false
  )!

  private let analyzer = SNAudioStreamAnalyzer(format: format)
  private let collector = SpeechWindowCollector()
  /// Recording position of the first sample fed: the analyzer counts from zero.
  private var origin: Int?

  init() throws {
    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
    request.windowDuration = Self.windowDuration
    request.overlapFactor = Self.overlapFactor
    try analyzer.add(request, withObserver: collector)
  }

  func analyze(_ chunk: Data, startingAt position: Int) -> [SpeechWindow] {
    let origin = origin ?? position
    self.origin = origin
    if let buffer = Self.makeBuffer(from: chunk) {
      // Results are delivered synchronously, on this thread.
      analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition(position - origin))
    }
    return collector.takeWindows().map { window in
      SpeechWindow(samples: window.samples.lowerBound + origin ..< window.samples.upperBound + origin, speechConfidence: window.speechConfidence)
    }
  }

  private static func makeBuffer(from chunk: Data) -> AVAudioPCMBuffer? {
    let sampleCount = chunk.count / MemoryLayout<Int16>.size
    guard sampleCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
          let channel = buffer.floatChannelData?[0] else { return nil }

    chunk.withUnsafeBytes { rawBuffer in
      for index in 0..<sampleCount {
        let sample = rawBuffer.loadUnaligned(fromByteOffset: index * MemoryLayout<Int16>.size, as: Int16.self)
        channel[index] = Float(sample) / Float(Int16.max)
      }
    }
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    return buffer
  }
}

/// Keeps the analyzer's results until they are taken; the lock covers a delivery on another thread.
private nonisolated final class SpeechWindowCollector: NSObject, SNResultsObserving, @unchecked Sendable {
  private static let speechLabel = "speech"

  private let windows = OSAllocatedUnfairLock(initialState: [SpeechWindow]())

  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let classification = result as? SNClassificationResult else { return }
    let window = SpeechWindow(
      samples: Self.sampleIndex(of: classification.timeRange.start) ..< Self.sampleIndex(of: classification.timeRange.end),
      speechConfidence: classification.classification(forIdentifier: Self.speechLabel)?.confidence ?? 0
    )
    windows.withLock { $0.append(window) }
  }

  func takeWindows() -> [SpeechWindow] {
    windows.withLock { windows in
      defer { windows.removeAll() }
      return windows
    }
  }

  private static func sampleIndex(of time: CMTime) -> Int {
    Int((time.seconds * Double(TranscriptionAudio.sampleRate)).rounded())
  }
}
