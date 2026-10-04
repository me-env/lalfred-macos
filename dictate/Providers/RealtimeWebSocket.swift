import Foundation


/// What the realtime clients share: running the socket, chunking audio and coding messages.
enum RealtimeWebSocket {
  /// One second of audio, the chunk size the ElevenLabs docs use; Mistral accepts up to 256 KiB per message.
  private static let audioChunkBytes = TranscriptionAudio.sampleRate * 2

  /// Opens the socket, runs `prepare`, then `send` and `receive` together, and returns the first transcript.
  static func transcribe(
    on webSocket: URLSessionWebSocketTask,
    provider: APIKeyProvider,
    prepare: () async throws -> Void = {},
    send: @escaping @Sendable () async throws -> Void,
    receive: @escaping @Sendable () async throws -> String
  ) async throws -> String {
    webSocket.resume()

    return try await withTaskCancellationHandler {
      do {
        try await prepare()

        return try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask {
            try await send()
            return nil
          }
          group.addTask {
            try await receive()
          }

          // Closing the socket unblocks whichever side is still waiting, so the group can return.
          while let result = try await group.next() {
            guard let transcript = result else { continue }
            webSocket.cancel(with: .normalClosure, reason: nil)
            return transcript
          }
          throw TranscriptionError.invalidResponse(provider)
        }
      } catch {
        webSocket.cancel(with: .goingAway, reason: nil)
        throw TranscriptionError.handshakeFailure(of: webSocket, provider: provider) ?? error
      }
    } onCancel: {
      webSocket.cancel(with: .goingAway, reason: nil)
    }
  }

  /// Sends the recording in one-second messages, each built by `encode`.
  static func sendAudio(
    _ audio: AsyncThrowingStream<Data, Error>,
    over webSocket: URLSessionWebSocketTask,
    encode: (Data) throws -> String
  ) async throws {
    for try await chunk in audio {
      var start = chunk.startIndex
      while start < chunk.endIndex {
        let end = min(start + audioChunkBytes, chunk.endIndex)
        try await webSocket.send(.string(encode(chunk[start..<end])))
        start = end
      }
    }
    try Task.checkCancellation()
  }

  static func encodeJSON<T: Encodable>(_ message: T) throws -> String {
    String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
  }

  static func data(of message: URLSessionWebSocketTask.Message) -> Data? {
    switch message {
    case .string(let text):
      return Data(text.utf8)
    case .data(let binary):
      return binary
    @unknown default:
      return nil
    }
  }
}
