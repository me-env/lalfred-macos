
protocol LLMProvider {
  func process(userPrompt: String, instruction: String) async throws -> String
}
