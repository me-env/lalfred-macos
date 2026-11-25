import Foundation
import os
import Testing
@testable import L_Alfred

struct SegmentedTranscriberTests {
  private struct SegmentFailure: Error {}
  private struct RecordingFailure: Error {}

  /// Records each request's audio and answers with `reply(audio)` once the audio ended. Requests run
  /// concurrently, so they are told apart by their audio, not by their start order.
  private final class FakeProvider: @unchecked Sendable {
    private let requests = OSAllocatedUnfairLock(initialState: [Data]())
    private let reply: @Sendable (Data) async throws -> String

    init(reply: @escaping @Sendable (Data) async throws -> String) {
      self.reply = reply
    }

    /// Ordered by length: the recordings below have segments of distinct lengths.
    var requestAudio: [Data] {
      requests.withLock { $0.sorted { $0.count < $1.count } }
    }

    func transcribe(_ audio: AsyncThrowingStream<Data, Error>) async throws -> String {
      var received = Data()
      for try await chunk in audio {
        received.append(chunk)
      }
      requests.withLock { $0.append(received) }
      return try await reply(received)
    }
  }

  /// The segments `AudioSegmenter` cuts the recording into.
  private func expectedSegments(of recording: TestRecording) -> [Data] {
    var segmenter = AudioSegmenter(makeDetector: FakeDetectorFactory(recording: recording).make)
    return segments(of: segmenter.append(recording.pcm) + segmenter.finish())
  }

  private func audioStream(of recording: TestRecording, endingWith error: Error? = nil) -> AsyncThrowingStream<Data, Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    for chunk in chunked(recording.pcm, sizes: [1_600, 3_200]) {
      continuation.yield(chunk)
    }
    continuation.finish(throwing: error)
    return stream
  }

  private func makeTranscriber(_ provider: FakeProvider, _ factory: FakeDetectorFactory) -> SegmentedTranscriber {
    SegmentedTranscriber(transcribeSegment: provider.transcribe, makeDetector: factory.make)
  }

  @Test func shortDictationIsOneRequest() async throws {
    let recording = TestRecording(duration: 12, pauses: [4 ..< 5])
    let provider = FakeProvider { _ in " Hello there. " }
    let factory = FakeDetectorFactory(recording: recording)

    let text = try await makeTranscriber(provider, factory).transcribe(audioStream(of: recording))

    #expect(text == "Hello there.")
    #expect(provider.requestAudio == [recording.pcm])
    #expect(factory.created.isEmpty)
  }

  @Test func joinsTextsInOrderWhenRequestsFinishOutOfOrder() async throws {
    let recording = TestRecording(duration: 70, pauses: [22 ..< 23, 45 ..< 46])
    let segments = expectedSegments(of: recording)
    let firstSegmentByteCount = segments[0].count
    let provider = FakeProvider { audio in
      // The first segment finishes last.
      try await Task.sleep(for: .milliseconds(audio.count == firstSegmentByteCount ? 300 : 10))
      return "\(audio.count) bytes."
    }

    let text = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    #expect(segments.count == 3)
    #expect(text == segments.map { "\($0.count) bytes." }.joined(separator: " "))
  }

  @Test func everyByteGoesToExactlyOneRequest() async throws {
    let recording = TestRecording(duration: 70, pauses: [22 ..< 23, 45 ..< 46])
    let provider = FakeProvider { _ in "text" }

    _ = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    let segments = expectedSegments(of: recording)
    #expect(segments.reduce(Data(), +) == recording.pcm)
    #expect(provider.requestAudio == segments.sorted { $0.count < $1.count })
  }

  @Test func failedSegmentFailsTheDictationAndCancelsTheOthers() async throws {
    let recording = TestRecording(duration: 50, pauses: [22 ..< 23])
    let firstSegmentByteCount = expectedSegments(of: recording)[0].count
    let provider = FakeProvider { audio in
      guard audio.count == firstSegmentByteCount else {
        try await Task.sleep(for: .seconds(30))
        return "too late"
      }
      throw SegmentFailure()
    }
    let clock = ContinuousClock()
    let start = clock.now

    await #expect(throws: SegmentFailure.self) {
      try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))
    }
    #expect(clock.now - start < .seconds(5))
  }

  @Test func recordingErrorFailsTheDictationAndCancelsRequests() async throws {
    let recording = TestRecording(duration: 30, pauses: [22 ..< 23])
    let provider = FakeProvider { _ in
      try await Task.sleep(for: .seconds(30))
      return "too late"
    }
    let clock = ContinuousClock()
    let start = clock.now

    await #expect(throws: RecordingFailure.self) {
      try await makeTranscriber(provider, FakeDetectorFactory(recording: recording))
        .transcribe(audioStream(of: recording, endingWith: RecordingFailure()))
    }
    #expect(clock.now - start < .seconds(5))
  }

  @Test func cancellingTheTranscriptionCancelsEveryRequest() async throws {
    let recording = TestRecording(duration: 50, pauses: [22 ..< 23])
    let provider = FakeProvider { _ in
      try await Task.sleep(for: .seconds(30))
      return "too late"
    }
    let transcriber = makeTranscriber(provider, FakeDetectorFactory(recording: recording))
    let audio = audioStream(of: recording)
    let clock = ContinuousClock()
    let start = clock.now

    let transcription = Task { try await transcriber.transcribe(audio) }
    try await Task.sleep(for: .milliseconds(200))
    transcription.cancel()

    await #expect(throws: CancellationError.self) {
      try await transcription.value
    }
    #expect(clock.now - start < .seconds(5))
  }
}
