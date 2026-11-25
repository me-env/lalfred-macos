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
    private let startCount = OSAllocatedUnfairLock(initialState: 0)
    private let reply: @Sendable (Data) async throws -> String

    init(reply: @escaping @Sendable (Data) async throws -> String) {
      self.reply = reply
    }

    /// Ordered by length: the recordings below have segments of distinct lengths.
    var requestAudio: [Data] {
      requests.withLock { $0.sorted { $0.count < $1.count } }
    }

    var startedRequestCount: Int {
      startCount.withLock { $0 }
    }

    func transcribe(_ audio: AsyncThrowingStream<Data, Error>) async throws -> String {
      startCount.withLock { $0 += 1 }
      var received = Data()
      for try await chunk in audio {
        received.append(chunk)
      }
      requests.withLock { $0.append(received) }
      return try await reply(received)
    }
  }

  /// The segments `AudioSegmenter` cuts the recording into, without a silent tail it drops.
  private func expectedSegments(of recording: TestRecording) -> [Data] {
    var segmenter = AudioSegmenter(makeDetector: FakeDetectorFactory(recording: recording).make)
    return segments(of: segmenter.append(recording.pcm) + segmenter.finish()).filter { !$0.isEmpty }
  }

  private func replyingWithByteCount() -> FakeProvider {
    FakeProvider { audio in "\(audio.count) bytes." }
  }

  /// Waits until `condition` holds, at most 5 s.
  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
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
    SegmentedTranscriber(transcribeSegment: provider.transcribe, makeDetector: factory.make, properNouns: [])
  }

  @Test func shortDictationIsOneRequest() async throws {
    let recording = TestRecording(duration: 12, pauses: [4 ..< 8])
    let provider = FakeProvider { _ in " Hello there. " }
    let factory = FakeDetectorFactory(recording: recording)

    let text = try await makeTranscriber(provider, factory).transcribe(audioStream(of: recording))

    #expect(text == "Hello there.")
    #expect(provider.requestAudio == [recording.pcm])
    #expect(factory.created.count == 1)
  }

  @Test func joinsTextsInOrderWhenRequestsFinishOutOfOrder() async throws {
    let recording = TestRecording(duration: 70, pauses: [22 ..< 25.5, 47 ..< 50.5])
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
    let recording = TestRecording(duration: 70, pauses: [22 ..< 25.5, 47 ..< 50.5])
    let provider = FakeProvider { _ in "text" }

    _ = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    let segments = expectedSegments(of: recording)
    #expect(segments.reduce(Data(), +) == recording.pcm)
    #expect(provider.requestAudio == segments.sorted { $0.count < $1.count })
  }

  @Test func silenceAfterTheLastCutIsNotRequested() async throws {
    let recording = TestRecording(duration: 70, pauses: [22 ..< 25.5, 47 ..< 70])
    let provider = replyingWithByteCount()

    let text = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    let segments = expectedSegments(of: recording)
    let sentByteCount = segments.reduce(0) { $0 + $1.count }
    #expect(segments.count == 2)
    #expect(provider.startedRequestCount == 2)
    #expect(text == segments.map { "\($0.count) bytes." }.joined(separator: " "))
    #expect(segments.reduce(Data(), +) == recording.pcm.prefix(sentByteCount))
    #expect(recording.pauseSamples[1].contains(sentByteCount / 2))
  }

  @Test func finalSegmentIsRequestedWhenNotClearlySilent() async throws {
    let ambiguous = TestRecording(duration: 70, pauses: [22 ..< 25.5, 47 ..< 69], unclear: [69 ..< 70])
    let speech = TestRecording(duration: 70, pauses: [22 ..< 25.5, 47 ..< 69.5])

    for recording in [ambiguous, speech] {
      let provider = replyingWithByteCount()

      _ = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

      #expect(provider.startedRequestCount == 3)
      #expect(provider.requestAudio.reduce(0) { $0 + $1.count } == recording.pcm.count)
    }
  }

  @Test func segmentRequestOpensOnlyOnceSoundIsHeard() async throws {
    let recording = TestRecording(duration: 40, pauses: [10 ..< 30])
    let pcm = recording.pcm
    let silenceEnd = 2 * samples(atSecond: 29)
    let provider = replyingWithByteCount()
    let (audio, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let transcriber = makeTranscriber(provider, FakeDetectorFactory(recording: recording))
    let transcription = Task { try await transcriber.transcribe(audio) }

    for chunk in chunked(pcm.prefix(silenceEnd), sizes: [3_200]) {
      continuation.yield(chunk)
    }
    try await waitUntil { provider.requestAudio.count == 1 }
    try await Task.sleep(for: .milliseconds(100))
    let startedDuringSilence = provider.startedRequestCount
    continuation.yield(pcm.suffix(from: silenceEnd))
    continuation.finish()
    _ = try await transcription.value

    #expect(startedDuringSilence == 1)
    #expect(provider.startedRequestCount == 2)
    #expect(provider.requestAudio.reduce(Data()) { $0 + $1 }.count == pcm.count)
  }

  @Test func shortDictationWithSpeechIsOneRequest() async throws {
    let recording = TestRecording(duration: 8, pauses: [])
    let provider = replyingWithByteCount()

    _ = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    #expect(provider.requestAudio == [recording.pcm])
  }

  @Test func silentDictationIsStillOneRequest() async throws {
    let recording = TestRecording(duration: 12, pauses: [0 ..< 12])
    let provider = replyingWithByteCount()

    _ = try await makeTranscriber(provider, FakeDetectorFactory(recording: recording)).transcribe(audioStream(of: recording))

    #expect(provider.requestAudio == [recording.pcm])
  }

  @Test func failedSegmentFailsTheDictationAndCancelsTheOthers() async throws {
    let recording = TestRecording(duration: 50, pauses: [22 ..< 25.5])
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
    let recording = TestRecording(duration: 30, pauses: [22 ..< 25.5])
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
    let recording = TestRecording(duration: 50, pauses: [22 ..< 25.5])
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
