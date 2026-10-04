import Foundation


/// Transcribes with Voxtral Mini Transcribe through Mistral's batch endpoint.
struct VoxtralClient {
  private static let apiKeyProvider = TranscriptionProvider.voxtral.apiKeyProvider

  private let languageCode: String?
  private let session: URLSession
  private let endpoint: URL = URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!

  init(
    languageCode: String? = nil,
    session: URLSession = .shared
  ) {
    self.languageCode = languageCode
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the Scribe clients.
  /// Raw PCM is not an accepted upload format, so the recording is collected and sent as a WAV file once it ends.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    let apiKey = try Self.apiKeyProvider.loadAPIKey()

    var pcm = Data()
    for try await chunk in audio {
      pcm.append(chunk)
    }
    try Task.checkCancellation()

    let form = makeForm(keyterms: keyterms)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.networkServiceType = .responsiveData
    request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let body = form.head + makeWAV(fromPCM: pcm) + form.tail
    let (data, response) = try await session.upload(for: request, from: body)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranscriptionError.invalidResponse(Self.apiKeyProvider)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw TranscriptionError.requestFailed(
        Self.apiKeyProvider,
        statusCode: httpResponse.statusCode,
        message: ServerErrorMessage.parse(data)
      )
    }

    guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
      throw TranscriptionError.invalidResponse(Self.apiKeyProvider)
    }
    return decoded.text
  }

  private func makeForm(keyterms: [String]) -> MultipartFormData {
    var form = MultipartFormData()

    form.appendField("model", value: "voxtral-mini-latest")

    // Sent as repeated fields, like the official SDK does.
    keyterms.forEach { keyterm in
      form.appendField("context_bias", value: keyterm)
    }

    if let languageCode {
      form.appendField("language", value: languageCode)
    }

    form.appendFileHeader(name: "file", filename: "audio.wav", contentType: "audio/wav")
    return form
  }

  /// Prepends a 44-byte RIFF header for 16 kHz mono 16-bit PCM.
  private func makeWAV(fromPCM pcm: Data) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(TranscriptionAudio.sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)

    var wav = Data()
    wav.append("RIFF")
    wav.appendLittleEndian(UInt32(36 + pcm.count))
    wav.append("WAVE")
    wav.append("fmt ")
    wav.appendLittleEndian(UInt32(16))
    wav.appendLittleEndian(UInt16(1))
    wav.appendLittleEndian(channels)
    wav.appendLittleEndian(UInt32(TranscriptionAudio.sampleRate))
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
