import Foundation


struct OpenAITranscriptPostProcessor: LLMProvider {
  enum OpenAITranscriptPostProcessorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case invalidLLMResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
      switch self {
      case .missingAPIKey:
        return "Missing OpenAI API key"
      case .invalidResponse:
        return "Unexpected API response"
      case .invalidLLMResponse:
        return "Unexpected LLM response"
      case let .requestFailed(statusCode, message):
        return "LLM request failed (\(statusCode)): \(message)"
      }
    }
  }

  private let apiKeyStore: APIKeyDefaultsStore
  private let session: URLSession
  private let endpoint: URL

  init(
    apiKeyStore: APIKeyDefaultsStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyOpenAI),
    session: URLSession = .shared,
    endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
  ) {
    self.apiKeyStore = apiKeyStore
    self.session = session
    self.endpoint = endpoint
  }

  func process(transcript: String, context: ModeTranscriptionContext) async throws -> String {
    let instruction = context.llmInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let apiKey = try loadAPIKey()
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let userPrompt = """
    Mode: \(context.modeTitle)
    Input transcript:
    \(transcript)
    """
    let payload = OpenAIChatCompletionRequest(
      model: "gpt-4.1",
      temperature: 0,
      messages: [
        .init(role: "system", content: instruction),
        .init(role: "user", content: userPrompt)
      ]
    )
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await session.data(for: request)
    let httpResponse = try unwrapHTTPResponse(response)

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw OpenAITranscriptPostProcessorError.requestFailed(
        statusCode: httpResponse.statusCode,
        message: message
      )
    }

    let llmResponse = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
    guard let content = llmResponse.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
      throw OpenAITranscriptPostProcessorError.invalidLLMResponse
    }

    return content
  }

  private func loadAPIKey() throws -> String {
    guard let rawKey = apiKeyStore.load() else {
      throw OpenAITranscriptPostProcessorError.missingAPIKey
    }

    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw OpenAITranscriptPostProcessorError.missingAPIKey
    }

    return key
  }

  private func unwrapHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenAITranscriptPostProcessorError.invalidResponse
    }

    return httpResponse
  }

  private func parseServerMessage(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
      return response.detail
    }

    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct OpenAIChatCompletionRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }

  let model: String
  let temperature: Double
  let messages: [Message]
}

private struct OpenAIChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }

    let message: Message
  }

  let choices: [Choice]
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}
