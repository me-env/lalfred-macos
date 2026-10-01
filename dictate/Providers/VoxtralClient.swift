import Foundation



enum VoxtralError: LocalizedError {
  case missingAPIKey
  case invalidResponse
  case requestFailed(statusCode: Int, message: String)
  case realtimeFailed(code: Int?, message: String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Missing Mistral API key"
    case .invalidResponse:
      return "Unexpected API response"
    case let .requestFailed(statusCode, message):
      return "Voxtral request failed (\(statusCode)): \(message)"
    case let .realtimeFailed(code, message):
      return "Voxtral realtime error (\(code.map(String.init) ?? "unknown")): \(message)"
    }
  }
}

/// Transcribes with Voxtral Mini Transcribe through Mistral's batch endpoint.
struct VoxtralClient {
  private static let sampleRate = 16_000

  private let languageCode: String?
  private let apiKeyStore: KeychainStore
  private let session: URLSession
  private let endpoint: URL = URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!

  init(
    languageCode: String? = nil,
    apiKeyStore: KeychainStore = KeychainStore(key: AppDefaultsKey.apiKeyMistral),
    session: URLSession = .shared
  ) {
    self.languageCode = languageCode
    self.apiKeyStore = apiKeyStore
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the Scribe clients.
  /// Raw PCM is not an accepted upload format, so the recording is collected and sent as a WAV file once it ends.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    let apiKey = try loadAPIKey()

    var pcm = Data()
    for try await chunk in audio {
      pcm.append(chunk)
    }
    try Task.checkCancellation()

    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.networkServiceType = .responsiveData
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let body = makeMultipartBody(boundary: boundary, wav: makeWAV(fromPCM: pcm), keyterms: keyterms)
    let (data, response) = try await session.upload(for: request, from: body)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoxtralError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw VoxtralError.requestFailed(statusCode: httpResponse.statusCode, message: message)
    }

    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func loadAPIKey() throws -> String {
    guard let rawKey = apiKeyStore.load() else {
      throw VoxtralError.missingAPIKey
    }

    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw VoxtralError.missingAPIKey
    }

    return key
  }

  private func parseServerMessage(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data),
       let message = response.message ?? response.detail {
      return message
    }

    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func makeMultipartBody(boundary: String, wav: Data, keyterms: [String]) -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    appendField("model", value: "voxtral-mini-latest", boundary: boundary, lineBreak: lineBreak, body: &body)

    // Up to 100 words or phrases, sent as repeated fields like the official SDK does.
    keyterms.prefix(100).forEach { keyterm in
      appendField("context_bias", value: keyterm, boundary: boundary, lineBreak: lineBreak, body: &body)
    }

    if let languageCode {
      appendField("language", value: languageCode, boundary: boundary, lineBreak: lineBreak, body: &body)
    }

    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(lineBreak)")
    body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)")
    body.append(wav)
    body.append("\(lineBreak)--\(boundary)--\(lineBreak)")

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

  /// Prepends a 44-byte RIFF header for 16 kHz mono 16-bit PCM.
  private func makeWAV(fromPCM pcm: Data) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(Self.sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)

    var wav = Data()
    wav.append("RIFF")
    wav.appendLittleEndian(UInt32(36 + pcm.count))
    wav.append("WAVE")
    wav.append("fmt ")
    wav.appendLittleEndian(UInt32(16))
    wav.appendLittleEndian(UInt16(1))
    wav.appendLittleEndian(channels)
    wav.appendLittleEndian(UInt32(Self.sampleRate))
    wav.appendLittleEndian(byteRate)
    wav.appendLittleEndian(blockAlign)
    wav.appendLittleEndian(bitsPerSample)
    wav.append("data")
    wav.appendLittleEndian(UInt32(pcm.count))
    wav.append(pcm)
    return wav
  }
}

private struct TranscriptionResponse: Decodable {
  let text: String
}

private struct ServerErrorResponse: Decodable {
  let message: String?
  let detail: String?

  enum CodingKeys: String, CodingKey {
    case message
    case detail
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Either field may hold a string or a structured object; only strings are useful to show.
    message = try? container.decodeIfPresent(String.self, forKey: .message)
    detail = try? container.decodeIfPresent(String.self, forKey: .detail)
  }
}

private extension Data {
  mutating func append(_ string: String) {
    if let encoded = string.data(using: .utf8) {
      append(encoded)
    }
  }

  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }
}
