
protocol LLMProvider {
  func process(transcript: String, context: ModeTranscriptionContext) async throws -> String
}
