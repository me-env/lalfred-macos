import Foundation


protocol STTProvider {
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String
}
