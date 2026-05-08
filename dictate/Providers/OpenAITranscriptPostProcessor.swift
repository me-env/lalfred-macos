import Foundation


enum OpenAITranscriptPostProcessorError: LocalizedError {
  case missingAPIKey
  case missingAuthToken
  case invalidProxyEndpoint
  case invalidResponse
  case invalidLLMResponse
  case requestFailed(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Missing OpenAI API key"
    case .missingAuthToken:
      return "Missing auth token"
    case .invalidProxyEndpoint:
      return "LLM proxy endpoint is not configured"
    case .invalidResponse:
      return "Unexpected API response"
    case .invalidLLMResponse:
      return "Unexpected LLM response"
    case let .requestFailed(statusCode, message):
      return "LLM request failed (\(statusCode)): \(message)"
    }
  }
}


struct OpenAITranscriptPostProcessor: LLMProvider {
  private let apiKeyStore: APIKeyDefaultsStore
  private let authTokenStore: APIKeyDefaultsStore
  private let session: URLSession
  private let directEndpoint: URL
  private let proxyEndpoint: URL?
  private let mode: TransportMode

  init(
    apiKeyStore: APIKeyDefaultsStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyOpenAI),
    authTokenStore: APIKeyDefaultsStore = APIKeyDefaultsStore(key: AppDefaultsKey.authToken),
    session: URLSession = .shared,
    directEndpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
    proxyEndpoint: URL? = OpenAITranscriptPostProcessor.defaultProxyEndpoint,
    mode: TransportMode = .direct
  ) {
    self.apiKeyStore = apiKeyStore
    self.authTokenStore = authTokenStore
    self.session = session
    self.directEndpoint = directEndpoint
    self.proxyEndpoint = proxyEndpoint
    self.mode = mode
  }

  func process(userPrompt: String, instruction: String) async throws -> String {
    let requestURL: URL
    var request: URLRequest

    switch mode {
    case .direct:
      requestURL = directEndpoint
      request = URLRequest(url: requestURL)
      let apiKey = try loadAPIKey()
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    case .proxy:
      requestURL = try requireProxyEndpoint()
      request = URLRequest(url: requestURL)
      let authToken = try loadAuthToken()
      print("authToken \(authToken)")
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }
    

    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let messages = [
      OpenAIChatCompletionRequest.Message(role: "system", content: instruction.trimmingCharacters(in: .whitespacesAndNewlines)),
      OpenAIChatCompletionRequest.Message(role: "user", content: userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
    ].filter { !$0.content.isEmpty }
    guard !messages.isEmpty else {
      return trimTrailingWhitespaceAndNewlines(userPrompt)
    }

    let payload = OpenAIChatCompletionRequest(
      model: "gpt-4.1-mini",
      temperature: 0,
      messages: messages
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
    guard let content = llmResponse.choices.first?.message.content.map(trimTrailingWhitespaceAndNewlines),
          !content.isEmpty else {
      throw OpenAITranscriptPostProcessorError.invalidLLMResponse
    }

    return content
  }

  private func requireProxyEndpoint() throws -> URL {
    guard let proxyEndpoint else {
      throw OpenAITranscriptPostProcessorError.invalidProxyEndpoint
    }
    return proxyEndpoint
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

  private func loadAuthToken() throws -> String {
    guard let rawToken = authTokenStore.load() else {
      throw OpenAITranscriptPostProcessorError.missingAuthToken
    }
    let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw OpenAITranscriptPostProcessorError.missingAuthToken
    }
    return token
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

  private func trimTrailingWhitespaceAndNewlines(_ text: String) -> String {
    var result = text
    while let lastScalar = result.unicodeScalars.last,
          CharacterSet.whitespacesAndNewlines.contains(lastScalar) {
      result.unicodeScalars.removeLast()
    }
    return result
  }

  static var defaultProxyEndpoint: URL {
    APIEndpoints.llmChat
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
