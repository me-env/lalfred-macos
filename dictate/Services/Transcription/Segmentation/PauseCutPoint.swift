import Foundation


/// Where to cut inside a pause, and the audio energy the pause is judged by. `audio` holds the
/// samples from recording position `audioStart` on.
nonisolated enum PauseCutPoint {
  /// 20 ms at 16 kHz.
  static let frameLength = 320

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

  /// Mean squared sample over `range`; nil unless `audio` holds all of it.
  static func meanEnergy(of range: Range<Int>, audio: Data, audioStart: Int) -> Double? {
    let audioEnd = audioStart + audio.count / MemoryLayout<Int16>.size
    guard !range.isEmpty, range.lowerBound >= audioStart, range.upperBound <= audioEnd else { return nil }
    return Double(energy(of: range, audio: audio, audioStart: audioStart)) / Double(range.count)
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
