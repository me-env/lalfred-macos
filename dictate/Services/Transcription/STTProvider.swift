import Foundation


/// The recording format every provider receives: mono 16-bit little-endian PCM at this rate.
nonisolated enum TranscriptionAudio {
  static let sampleRate = 16_000
}

protocol STTProvider {
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String
}
