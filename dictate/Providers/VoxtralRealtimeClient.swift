import Foundation


/// Streams audio to Voxtral Mini Transcribe Realtime over a WebSocket and waits for the final transcript once the audio ends.
struct VoxtralRealtimeClient {
  private static let apiKeyProvider = TranscriptionProvider.voxtralRealtime.apiKeyProvider

  private let session: URLSession
  private let endpoint: URL = URL(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime")!

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the batch client.
  /// The realtime model detects the language itself and takes no key terms.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    var request = URLRequest(url: makeURL())
    request.setValue("Bearer \(try Self.apiKeyProvider.loadAPIKey())", forHTTPHeaderField: "Authorization")

    let webSocket = session.webSocketTask(with: request)

    return try await RealtimeWebSocket.transcribe(
      on: webSocket,
      provider: Self.apiKeyProvider,
      prepare: {
        try await Self.waitForSessionCreated(on: webSocket)
        try await webSocket.send(.string(RealtimeWebSocket.encodeJSON(SessionUpdate())))
      },
      send: { try await Self.send(audio, to: webSocket) },
      receive: { try await Self.receiveTranscript(from: webSocket) }
    )
  }

  private func makeURL() -> URL {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "model", value: "voxtral-mini-transcribe-realtime-2602")]
    return components.url!
  }

  /// The session must exist before its audio format can be set.
  private static func waitForSessionCreated(on webSocket: URLSessionWebSocketTask) async throws {
    while true {
      guard let event = decode(try await webSocket.receive()) else { continue }

      switch event.type {
      case "session.created":
        return
      case "error":
        throw realtimeError(from: event)
      default:
        continue
      }
    }
  }

  private static func send(_ audio: AsyncThrowingStream<Data, Error>, to webSocket: URLSessionWebSocketTask) async throws {
    try await RealtimeWebSocket.sendAudio(audio, over: webSocket) { chunk in
      try RealtimeWebSocket.encodeJSON(InputAudioAppend(audio: chunk))
    }
    try await webSocket.send(.string(RealtimeWebSocket.encodeJSON(InputAudioControl(type: "input_audio.flush"))))
    try await webSocket.send(.string(RealtimeWebSocket.encodeJSON(InputAudioControl(type: "input_audio.end"))))
  }

  /// Returns the final transcript, falling back on the streamed deltas if the socket closes before it arrives.
  private static func receiveTranscript(from webSocket: URLSessionWebSocketTask) async throws -> String {
    var streamedText = ""

    while true {
      let message: URLSessionWebSocketTask.Message
      do {
        message = try await webSocket.receive()
      } catch {
        if !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return streamedText
        }
        throw error
      }

      guard let event = decode(message) else { continue }

      switch event.type {
      case "transcription.text.delta":
        streamedText += event.text ?? ""
      case "transcription.done":
        return event.text ?? streamedText
      case "error":
        throw realtimeError(from: event)
      default:
        // Session updates, detected language and segments carry nothing needed here.
        continue
      }
    }
  }

  /// Realtime error codes are not documented; HTTP-like ones are treated like the batch endpoint's statuses.
  private static func realtimeError(from event: RealtimeEvent) -> TranscriptionError {
    let code = event.error?.code
    return .realtimeFailed(
      apiKeyProvider,
      code: code.map(String.init) ?? "unknown",
      message: event.error?.message ?? "Realtime transcription error",
      isTransient: code.map { $0 == 429 || (500..<600).contains($0) } ?? false
    )
  }

  private static func decode(_ message: URLSessionWebSocketTask.Message) -> RealtimeEvent? {
    guard let data = RealtimeWebSocket.data(of: message) else { return nil }
    return try? JSONDecoder().decode(RealtimeEvent.self, from: data)
  }
}

private struct SessionUpdate: Encodable {
  struct Session: Encodable {
    struct AudioFormat: Encodable {
      let encoding = "pcm_s16le"
      let sampleRate = TranscriptionAudio.sampleRate

      enum CodingKeys: String, CodingKey {
        case encoding
        case sampleRate = "sample_rate"
      }
    }

    let audioFormat = AudioFormat()

    enum CodingKeys: String, CodingKey {
      case audioFormat = "audio_format"
    }
  }

  let type = "session.update"
  let session = Session()
}

private struct InputAudioAppend: Encodable {
  let type = "input_audio.append"
  let audio: String

  init(audio: Data) {
    self.audio = audio.base64EncodedString()
  }
}

private struct InputAudioControl: Encodable {
  let type: String
}

private struct RealtimeEvent: Decodable {
  struct ErrorDetail: Decodable {
    let message: String?
    let code: Int?

    enum CodingKeys: String, CodingKey {
      case message
      case code
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      code = try? container.decodeIfPresent(Int.self, forKey: .code)
      // The message is either a string or an object carrying a `detail` string.
      if let text = try? container.decodeIfPresent(String.self, forKey: .message) {
        message = text
      } else {
        message = (try? container.decodeIfPresent(MessageObject.self, forKey: .message))?.detail
      }
    }
  }

  struct MessageObject: Decodable {
    let detail: String?
  }

  let type: String
  let text: String?
  let error: ErrorDetail?
}
