//
//  ScribeClient.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation

struct ScribeClient {
  enum ScribeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyTranscript
    
    var errorDescription: String? {
      switch self {
      case .missingAPIKey:
        return "Missing ElevenLabs API key"
      case .invalidResponse:
        return "Unexpected API response"
      case let .requestFailed(statusCode, message):
        return "Scribe request failed (\(statusCode)): \(message)"
      case .emptyTranscript:
        return "No speech recognized"
      }
    }
  }
  
  private let apiKeyStore: APIKeyDefaultsStore
  private let session: URLSession
  private let endpoint: URL
  private let userDefaults: UserDefaults
  
  init(
    apiKeyStore: APIKeyDefaultsStore = APIKeyDefaultsStore(key: "apiKey.11l"),
    session: URLSession = .shared,
    endpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
    userDefaults: UserDefaults = .standard
  ) {
    self.apiKeyStore = apiKeyStore
    self.session = session
    self.endpoint = endpoint
    self.userDefaults = userDefaults
  }
  
  func transcribeAudio(at fileURL: URL) async throws -> String {
    let apiKey = try loadAPIKey()
    let boundary = "Boundary-\(UUID().uuidString)"
    let body = try makeMultipartBody(fileURL: fileURL, boundary: boundary)
    
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    let (data, response) = try await session.upload(for: request, from: body)
    let httpResponse = try unwrapHTTPResponse(response)
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw ScribeError.requestFailed(statusCode: httpResponse.statusCode, message: message)
    }
    
    let transcript = try parseTranscript(from: data)
    guard !transcript.isEmpty else {
      throw ScribeError.emptyTranscript
    }
    
    return transcript
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
  
  private func makeMultipartBody(fileURL: URL, boundary: String) throws -> Data {
    var body = Data()
    let lineBreak = "\r\n"
    let model = "scribe_v2"
    
    appendField("model_id", value: model, boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("no_verbatim", value: "true", boundary: boundary, lineBreak: lineBreak, body: &body)
    
    let keyterms = loadKeyterms()
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
  
  private func loadKeyterms() -> [String] {
    guard let data = userDefaults.data(forKey: "savedWords"),
          let rawWords = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    
    var seen = Set<String>()
    return rawWords
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { $0.count <= 50 }
      .filter {
        let normalized = $0.lowercased()
        if seen.contains(normalized) {
          return false
        }
        seen.insert(normalized)
        return true
      }
      .prefix(1000)
      .map { $0 }
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
