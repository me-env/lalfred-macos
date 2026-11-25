import Foundation


/// Where to cut a recording: on the quietest frame of the first window without speech.
nonisolated enum PauseCutPoint {
  static let speechConfidenceThreshold = 0.5
  /// 20 ms at 16 kHz.
  static let frameLength = 320

  /// Nil while every window holds speech. `audio` holds the samples from `audioStart` on; windows
  /// starting before it are ignored, their audio is already sent.
  static func find(in windows: [SpeechWindow], audio: Data, audioStart: Int) -> Int? {
    let audioEnd = audioStart + audio.count / MemoryLayout<Int16>.size
    let pause = windows.first { window in
      window.speechConfidence < speechConfidenceThreshold
        && window.samples.lowerBound >= audioStart
        && window.samples.upperBound <= audioEnd
    }
    guard let pause else { return nil }
    return quietestFrameCenter(in: pause.samples, audio: audio, audioStart: audioStart)
  }

  /// The middle of the lowest-energy frame in `range`, the first one on a tie.
  static func quietestFrameCenter(in range: Range<Int>, audio: Data, audioStart: Int) -> Int {
    guard range.count > frameLength else { return range.lowerBound + range.count / 2 }

    let frameStarts = stride(from: range.lowerBound, through: range.upperBound - frameLength, by: frameLength)
    let energies = frameStarts.map { start in
      (start: start, energy: energy(of: start ..< start + frameLength, audio: audio, audioStart: audioStart))
    }
    let quietest = energies.min { $0.energy < $1.energy }!
    return quietest.start + frameLength / 2
  }

  private static func energy(of frame: Range<Int>, audio: Data, audioStart: Int) -> Int64 {
    audio.withUnsafeBytes { rawBuffer in
      frame.reduce(Int64(0)) { sum, position in
        let sample = Int64(rawBuffer.loadUnaligned(fromByteOffset: (position - audioStart) * MemoryLayout<Int16>.size, as: Int16.self))
        return sum + sample * sample
      }
    }
  }
}
