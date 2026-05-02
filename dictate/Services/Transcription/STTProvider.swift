import Foundation


protocol STTProvider {
  func transcribeAudio(at fileURL: URL, additionalVocabulary: [String]) async throws -> String
}
