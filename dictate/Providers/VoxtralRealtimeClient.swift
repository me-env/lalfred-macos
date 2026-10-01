import Foundation


/// Streams audio to Voxtral Mini Transcribe Realtime over a WebSocket and waits for the final transcript once the audio ends.
struct VoxtralRealtimeClient {
  /// One second of 16 kHz s16le audio; the API accepts up to 256 KiB per message.
  private static let maxChunkBytes = 32_000
  private static let sampleRate = 16_000

  private let apiKeyStore: KeychainStore
  private let session: URLSession
  private let endpoint: URL = URL(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime")!

  init(
    apiKeyStore: KeychainStore = KeychainStore(key: AppDefaultsKey.apiKeyMistral),
    session: URLSession = .shared
  ) {
    self.apiKeyStore = apiKeyStore
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the batch client.
  /// The realtime model detects the language itself and takes no key terms.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    var request = URLRequest(url: makeURL())
    request.setValue("Bearer \(try loadAPIKey())", forHTTPHeaderField: "Authorization")

    let webSocket = session.webSocketTask(with: request)
    webSocket.resume()

    return try await withTaskCancellationHandler {
      do {
        try await Self.waitForSessionCreated(on: webSocket)
        try await webSocket.send(.string(Self.encode(SessionUpdate())))

        return try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask {
            try await Self.send(audio, to: webSocket)
            return nil
          }
          group.addTask {
            try await Self.receiveTranscript(from: webSocket)
          }

          // Closing the socket unblocks whichever side is still waiting, so the group can return.
          while let result = try await group.next() {
            guard let transcript = result else { continue }
            webSocket.cancel(with: .normalClosure, reason: nil)
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          }
          throw VoxtralError.invalidResponse
        }
      } catch {
        webSocket.cancel(with: .goingAway, reason: nil)
        throw error
      }
    } onCancel: {
      webSocket.cancel(with: .goingAway, reason: nil)
    }
  }

  private func makeURL() -> URL {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "model", value: "voxtral-mini-transcribe-realtime-2602")]
    return components.url!
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
    for try await chunk in audio {
      var start = chunk.startIndex
      while start < chunk.endIndex {
        let end = min(start + maxChunkBytes, chunk.endIndex)
        try await webSocket.send(.string(encode(InputAudioAppend(audio: chunk[start..<end]))))
        start = end
      }
    }

    try Task.checkCancellation()
    try await webSocket.send(.string(encode(InputAudioControl(type: "input_audio.flush"))))
    try await webSocket.send(.string(encode(InputAudioControl(type: "input_audio.end"))))
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

  private static func realtimeError(from event: RealtimeEvent) -> VoxtralError {
    .realtimeFailed(
      code: event.error?.code,
      message: event.error?.message ?? "Realtime transcription error"
    )
  }

  private static func encode<T: Encodable>(_ message: T) throws -> String {
    String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
  }

  private static func decode(_ message: URLSessionWebSocketTask.Message) -> RealtimeEvent? {
    let data: Data
    switch message {
    case .string(let text):
      data = Data(text.utf8)
    case .data(let binary):
      data = binary
    @unknown default:
      return nil
    }

    return try? JSONDecoder().decode(RealtimeEvent.self, from: data)
  }
}

private struct SessionUpdate: Encodable {
  struct Session: Encodable {
    struct AudioFormat: Encodable {
      let encoding = "pcm_s16le"
      let sampleRate = 16_000

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
