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

  /// Streams `audio` (16 kHz mono s16le PCM) into the request body while it is being recorded.
  /// The server still transcribes the complete recording with the batch model.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    let boundary = "Boundary-\(UUID().uuidString)"
    let body = StreamedRequestBody()
    var request = URLRequest(url: directEndpoint)

    request.httpMethod = "POST"
    request.networkServiceType = .responsiveData
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(try loadAPIKey(), forHTTPHeaderField: "xi-api-key")
    request.httpBodyStream = body.inputStream

    body.write(makeMultipartHead(boundary: boundary, keyterms: keyterms))

    let feeder = Task {
      do {
        for try await chunk in audio {
          body.write(chunk)
        }
        try Task.checkCancellation()
        body.write(Data("\r\n--\(boundary)--\r\n".utf8))
      } catch {
        // Closing without the closing boundary makes the server reject the truncated request.
      }
      body.finish()
    }
    defer { feeder.cancel() }

    let (data, response) = try await withTaskCancellationHandler {
      try await session.data(for: request)
    } onCancel: {
      feeder.cancel()
    }
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

  /// Everything before the audio bytes: the form fields and the file part header.
  private func makeMultipartHead(boundary: String, keyterms: [String]) -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    appendField("model_id", value: "scribe_v2", boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("file_format", value: "pcm_s16le_16", boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("no_verbatim", value: "true", boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("tag_audio_events", value: "false", boundary: boundary, lineBreak: lineBreak, body: &body)

    keyterms.forEach { keyterm in
      appendField("keyterms", value: keyterm, boundary: boundary, lineBreak: lineBreak, body: &body)
    }

    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.pcm\"\(lineBreak)")
    body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)")

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
}

private struct TranscriptionResponse: Decodable {
  let text: String
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}

/// Pipes bytes written from any thread into an `InputStream` that URLSession reads as the request body.
private nonisolated final class StreamedRequestBody: @unchecked Sendable {
  let inputStream: InputStream
  private let outputStream: OutputStream
  private let queue = DispatchQueue(label: "lalfred.scribe.request-body", qos: .userInitiated)

  init(bufferSize: Int = 64 * 1024) {
    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(withBufferSize: bufferSize, inputStream: &input, outputStream: &output)
    inputStream = input!
    outputStream = output!
    outputStream.open()
  }

  /// Enqueues `data`; writes block on a private queue until URLSession reads them.
  func write(_ data: Data) {
    queue.async { [outputStream] in
      Self.writeAll(data, to: outputStream)
    }
  }

  func finish() {
    queue.async { [outputStream] in
      outputStream.close()
    }
  }

  private static func writeAll(_ data: Data, to stream: OutputStream) {
    data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      var offset = 0
      while offset < data.count {
        let written = stream.write(base + offset, maxLength: data.count - offset)
        guard written > 0 else { return }
        offset += written
      }
    }
  }
}

private extension Data {
  mutating func append(_ string: String) {
    if let encoded = string.data(using: .utf8) {
      append(encoded)
    }
  }
}
