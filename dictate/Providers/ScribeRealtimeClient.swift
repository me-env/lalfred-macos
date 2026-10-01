import Foundation


/// Streams audio to Scribe v2 Realtime over a WebSocket and commits once, when the audio ends.
struct ScribeRealtimeClient {
  struct Options {
    var languageCode: String?
    var secondaryLanguages: [String] = []
    var transcriptEdit: String?
  }

  /// One second of 16 kHz s16le audio, the chunk size the API docs use.
  private static let maxChunkBytes = 32_000
  private static let sampleRate = 16_000

  private let options: Options
  private let apiKeyStore: KeychainStore
  private let session: URLSession
  private let endpoint: URL = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!

  init(
    options: Options,
    apiKeyStore: KeychainStore = KeychainStore(key: AppDefaultsKey.apiKeyElevenLabs),
    session: URLSession = .shared
  ) {
    self.options = options
    self.apiKeyStore = apiKeyStore
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the batch client.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    var request = URLRequest(url: makeURL(keyterms: keyterms))
    request.setValue(try loadAPIKey(), forHTTPHeaderField: "xi-api-key")

    let webSocket = session.webSocketTask(with: request)
    let waitsForEdit = options.transcriptEdit != nil
    webSocket.resume()

    return try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: String?.self) { group in
        group.addTask {
          try await Self.send(audio, to: webSocket)
          return nil
        }
        group.addTask {
          try await Self.receiveTranscript(from: webSocket, waitsForEdit: waitsForEdit)
        }

        // Closing the socket unblocks whichever side is still waiting, so the group can return.
        do {
          while let result = try await group.next() {
            guard let transcript = result else { continue }
            webSocket.cancel(with: .normalClosure, reason: nil)
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          }
          throw ScribeError.invalidResponse
        } catch {
          webSocket.cancel(with: .goingAway, reason: nil)
          throw error
        }
      }
    } onCancel: {
      webSocket.cancel(with: .goingAway, reason: nil)
    }
  }

  private func makeURL(keyterms: [String]) -> URL {
    var queryItems = [
      URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
      URLQueryItem(name: "audio_format", value: "pcm_16000"),
      URLQueryItem(name: "commit_strategy", value: "manual"),
      URLQueryItem(name: "no_verbatim", value: "true"),
    ]

    if let languageCode = options.languageCode {
      queryItems.append(URLQueryItem(name: "language_code", value: languageCode))
    }
    // Array parameters are sent as repeated keys, like the official SDK does.
    queryItems += options.secondaryLanguages.map { URLQueryItem(name: "secondary_languages", value: $0) }
    queryItems += keyterms.map { URLQueryItem(name: "keyterms", value: $0) }
    if let transcriptEdit = options.transcriptEdit {
      queryItems.append(URLQueryItem(name: "transcript_edit", value: transcriptEdit))
    }

    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = queryItems
    // `URLComponents` leaves "+" unescaped, which servers read as a space.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url!
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

  private static func send(_ audio: AsyncThrowingStream<Data, Error>, to webSocket: URLSessionWebSocketTask) async throws {
    for try await chunk in audio {
      var start = chunk.startIndex
      while start < chunk.endIndex {
        let end = min(start + maxChunkBytes, chunk.endIndex)
        try await webSocket.send(.string(encode(InputAudioChunk(audio: chunk[start..<end], commit: false))))
        start = end
      }
    }

    try Task.checkCancellation()
    try await webSocket.send(.string(encode(InputAudioChunk(audio: Data(), commit: true))))
  }

  /// Returns the committed transcript, or its edited version when a transcript edit was requested.
  private static func receiveTranscript(from webSocket: URLSessionWebSocketTask, waitsForEdit: Bool) async throws -> String {
    var committedTranscript: String?

    while true {
      let message: URLSessionWebSocketTask.Message
      do {
        message = try await webSocket.receive()
      } catch {
        // The edit never came but the transcript did: better than failing.
        if let committedTranscript {
          return committedTranscript
        }
        throw error
      }

      guard let event = decode(message) else { continue }

      switch event.messageType {
      case "committed_transcript":
        let text = event.text ?? ""
        guard waitsForEdit, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return text
        }
        committedTranscript = text
      case "edited_transcript":
        return event.editedText ?? event.text ?? committedTranscript ?? ""
      default:
        // Partial transcripts, session info and warnings carry no `error`.
        if let error = event.error {
          throw ScribeError.realtimeFailed(type: event.messageType, message: error)
        }
      }
    }
  }

  private static func encode(_ chunk: InputAudioChunk) throws -> String {
    String(decoding: try JSONEncoder().encode(chunk), as: UTF8.self)
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

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(RealtimeEvent.self, from: data)
  }
}

private struct InputAudioChunk: Encodable {
  let messageType = "input_audio_chunk"
  let audioBase64: String
  let commit: Bool
  let sampleRate = 16_000

  init(audio: Data, commit: Bool) {
    self.audioBase64 = audio.base64EncodedString()
    self.commit = commit
  }

  enum CodingKeys: String, CodingKey {
    case messageType = "message_type"
    case audioBase64 = "audio_base_64"
    case commit
    case sampleRate = "sample_rate"
  }
}

private struct RealtimeEvent: Decodable {
  let messageType: String
  let text: String?
  let editedText: String?
  let error: String?
}
