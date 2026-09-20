import Foundation


enum ScribeError: LocalizedError {
  case missingAPIKey
  case invalidResponse
  case requestFailed(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Missing ElevenLabs API key"
    case .invalidResponse:
      return "Unexpected API response"
    case let .requestFailed(statusCode, message):
      return "Scribe request failed (\(statusCode)): \(message)"
    }
  }
}


struct ScribeClient {
  private let apiKeyStore: KeychainStore
  private let session: URLSession
  private let directEndpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

  init(
    apiKeyStore: KeychainStore = KeychainStore(key: AppDefaultsKey.apiKeyElevenLabs),
    session: URLSession = .shared
  ) {
    self.apiKeyStore = apiKeyStore
    self.session = session
  }

  func transcribeAudio(at fileURL: URL, keyterms: [String]) async throws -> String {
    let boundary = "Boundary-\(UUID().uuidString)"
    let body = try makeMultipartBody(
      fileURL: fileURL,
      boundary: boundary,
      keyterms: keyterms
    )
    var request = URLRequest(url: directEndpoint)
    
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(try loadAPIKey(), forHTTPHeaderField: "xi-api-key")

    let (data, response) = try await session.upload(for: request, from: body)
    let httpResponse = try unwrapHTTPResponse(response)

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw ScribeError.requestFailed(statusCode: httpResponse.statusCode, message: message)
    }

    return try parseTranscript(from: data)
  }

  private func loadAPIKey() throws -> String {
    guard let rawKey = apiKeyStore.load() else {
      throw ScribeError.missingAPIKey
    }

    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw ScribeError.missingAPIKey
    }

    return key
  }

  private func unwrapHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ScribeError.invalidResponse
    }

    return httpResponse
  }

  private func parseTranscript(from data: Data) throws -> String {
    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func parseServerMessage(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
      return response.detail
    }

    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func makeMultipartBody(
    fileURL: URL,
    boundary: String,
    keyterms: [String]
  ) throws -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    appendField("model_id", value: "scribe_v2", boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("no_verbatim", value: "true", boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("tag_audio_events", value: "false", boundary: boundary, lineBreak: lineBreak, body: &body)

    keyterms.forEach { keyterm in
      appendField("keyterms", value: keyterm, boundary: boundary, lineBreak: lineBreak, body: &body)
    }

    let filename = fileURL.lastPathComponent
    let mimeType = mimeType(for: fileURL.pathExtension)
    let fileData = try Data(contentsOf: fileURL)

    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)")
    body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
    body.append(fileData)
    body.append(lineBreak)
    body.append("--\(boundary)--\(lineBreak)")

    return body
  }

  private func appendField(
    _ name: String,
    value: String,
    boundary: String,
    lineBreak: String,
    body: inout Data
  ) {
    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
    body.append("\(value)\(lineBreak)")
  }

  private func mimeType(for pathExtension: String) -> String {
    switch pathExtension.lowercased() {
    case "m4a":
      return "audio/m4a"
    case "wav":
      return "audio/wav"
    case "mp3":
      return "audio/mpeg"
    default:
      return "application/octet-stream"
    }
  }
}

private struct TranscriptionResponse: Decodable {
  let text: String
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}

private extension Data {
  mutating func append(_ string: String) {
    if let encoded = string.data(using: .utf8) {
      append(encoded)
    }
  }
}
