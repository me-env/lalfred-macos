import Foundation


protocol STTProvider {
  func transcribeAudio(at fileURL: URL, keyterms: [String]) async throws -> String
}
