import Foundation


/// Streams audio to Scribe v2 Realtime over a WebSocket and commits once, when the audio ends.
struct ScribeRealtimeClient {
  struct Options {
    var languageCode: String?
    var secondaryLanguages: [String] = []
    var transcriptEdit: String?
  }

  private static let apiKeyProvider = TranscriptionProvider.scribeV2Realtime.apiKeyProvider
  /// Error events worth retrying; the others come from the request itself.
  private static let transientErrorTypes: Set<String> = ["rate_limited", "queue_overflow", "resource_exhausted", "transcriber_error"]

  private let options: Options
  private let session: URLSession
  private let endpoint: URL = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!

  init(
    options: Options,
    session: URLSession = .shared
  ) {
    self.options = options
    self.session = session
  }

  /// Expects 16 kHz mono s16le PCM, like the batch client.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    var request = URLRequest(url: makeURL(keyterms: keyterms))
    request.setValue(try Self.apiKeyProvider.loadAPIKey(), forHTTPHeaderField: "xi-api-key")

    let webSocket = session.webSocketTask(with: request)
    let waitsForEdit = options.transcriptEdit != nil

    return try await RealtimeWebSocket.transcribe(
      on: webSocket,
      provider: Self.apiKeyProvider,
      send: { try await Self.send(audio, to: webSocket) },
      receive: { try await Self.receiveTranscript(from: webSocket, waitsForEdit: waitsForEdit) }
    )
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

  private static func send(_ audio: AsyncThrowingStream<Data, Error>, to webSocket: URLSessionWebSocketTask) async throws {
    try await RealtimeWebSocket.sendAudio(audio, over: webSocket) { chunk in
      try RealtimeWebSocket.encodeJSON(InputAudioChunk(audio: chunk, commit: false))
    }
    try await webSocket.send(.string(RealtimeWebSocket.encodeJSON(InputAudioChunk(audio: Data(), commit: true))))
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
          throw TranscriptionError.realtimeFailed(
            apiKeyProvider,
            code: event.messageType,
            message: error,
            isTransient: transientErrorTypes.contains(event.messageType)
          )
        }
      }
    }
  }

  private static func decode(_ message: URLSessionWebSocketTask.Message) -> RealtimeEvent? {
    guard let data = RealtimeWebSocket.data(of: message) else { return nil }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(RealtimeEvent.self, from: data)
  }
}

private struct InputAudioChunk: Encodable {
  let messageType = "input_audio_chunk"
  let audioBase64: String
  let commit: Bool
  let sampleRate = TranscriptionAudio.sampleRate

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
