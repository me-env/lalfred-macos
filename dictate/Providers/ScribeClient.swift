import Foundation


struct ScribeClient {
  private static let apiKeyProvider = TranscriptionProvider.scribeV2.apiKeyProvider

  private let languageCode: String?
  private let transcriptEdit: String?
  private let session: URLSession
  private let directEndpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

  init(
    languageCode: String? = nil,
    transcriptEdit: String? = nil,
    session: URLSession = .shared
  ) {
    self.languageCode = languageCode
    self.transcriptEdit = transcriptEdit
    self.session = session
  }

  /// Streams `audio` (16 kHz mono s16le PCM) into the request body while it is being recorded.
  /// The server still transcribes the complete recording with the batch model.
  func transcribeAudio(_ audio: AsyncThrowingStream<Data, Error>, keyterms: [String]) async throws -> String {
    let form = makeForm(keyterms: keyterms)
    let body = StreamedRequestBody()
    var request = URLRequest(url: directEndpoint)

    request.httpMethod = "POST"
    request.networkServiceType = .responsiveData
    request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(try Self.apiKeyProvider.loadAPIKey(), forHTTPHeaderField: "xi-api-key")
    request.httpBodyStream = body.inputStream

    body.write(form.head)

    // Returns the recording's error so it can be reported instead of the server's reply to the truncated upload.
    let feeder = Task { () -> Error? in
      defer { body.finish() }
      do {
        for try await chunk in audio {
          body.write(chunk)
        }
        try Task.checkCancellation()
        body.write(form.tail)
        return nil
      } catch {
        // Closing without the closing boundary makes the server reject the truncated request.
        return error
      }
    }
    defer { feeder.cancel() }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await withTaskCancellationHandler {
        try await session.data(for: request)
      } onCancel: {
        feeder.cancel()
      }
    } catch {
      throw await recordingError(from: feeder) ?? error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranscriptionError.invalidResponse(Self.apiKeyProvider)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw await recordingError(from: feeder) ?? TranscriptionError.requestFailed(
        Self.apiKeyProvider,
        statusCode: httpResponse.statusCode,
        message: ServerErrorMessage.parse(data)
      )
    }

    return try parseTranscript(from: data)
  }

  /// The recording's own failure, if it had one; a feeder cancelled because the request ended first doesn't count.
  private func recordingError(from feeder: Task<Error?, Never>) async -> Error? {
    feeder.cancel()
    guard let error = await feeder.value, !(error is CancellationError) else { return nil }
    return error
  }

  private func parseTranscript(from data: Data) throws -> String {
    guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
      throw TranscriptionError.invalidResponse(Self.apiKeyProvider)
    }
    // A failed edit comes back with kind "error"; the original transcript is still usable.
    if let edited = decoded.editedTranscript, edited.kind == "transcript", let editedText = edited.text {
      return editedText
    }
    return decoded.text
  }

  /// Everything before the audio bytes: the form fields and the file part header.
  private func makeForm(keyterms: [String]) -> MultipartFormData {
    var form = MultipartFormData()

    form.appendField("model_id", value: "scribe_v2")
    form.appendField("file_format", value: "pcm_s16le_16")
    form.appendField("no_verbatim", value: "true")
    form.appendField("tag_audio_events", value: "false")

    keyterms.forEach { keyterm in
      form.appendField("keyterms", value: keyterm)
    }

    if let languageCode {
      form.appendField("language_code", value: languageCode)
    }

    if let transcriptEdit {
      form.appendField("transcript_edit", value: transcriptEdit)
    }

    form.appendFileHeader(name: "file", filename: "audio.pcm", contentType: "application/octet-stream")
    return form
  }
}

private struct TranscriptionResponse: Decodable {
  struct EditedTranscript: Decodable {
    let kind: String
    let text: String?
  }

  let text: String
  let editedTranscript: EditedTranscript?

  enum CodingKeys: String, CodingKey {
    case text
    case editedTranscript = "edited_transcript"
  }
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
    queue.async { [self] in
      Self.writeAll(data, to: outputStream)
    }
  }

  func finish() {
    queue.async { [self] in
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
