import Foundation


/// Transcribes a recording as one request per segment, cut at pauses by `AudioSegmenter`, so earlier
/// segments are transcribed while the user still speaks. A segment's request opens with its first
/// audio, so a segment the segmenter drops is never requested. Texts are joined in recording order.
nonisolated struct SegmentedTranscriber {
  typealias SegmentTranscription = @Sendable (AsyncThrowingStream<Data, Error>) async throws -> String

  /// The segment receiving audio, nil from a cut until the next segment's first audio.
  private struct Segments {
    var latestIndex: Int
    var open: AsyncThrowingStream<Data, Error>.Continuation?
  }

  private typealias SegmentRequests = ThrowingTaskGroup<(index: Int, text: String), Error>

  let transcribeSegment: SegmentTranscription
  let makeDetector: @Sendable () -> VoiceActivityDetecting?
  /// Words that keep their capital where a segment continues the previous one's sentence.
  let properNouns: Set<String>

  /// Throws the recording's error, or the first failed segment's; the other requests are then cancelled.
  @concurrent
  func transcribe(_ audio: AsyncThrowingStream<Data, Error>) async throws -> String {
    try await withThrowingTaskGroup(of: (index: Int, text: String).self) { requests in
      var segments = Segments(latestIndex: 0, open: startRequest(index: 0, in: &requests))
      do {
        var segmenter = AudioSegmenter(makeDetector: makeDetector)
        for try await chunk in audio {
          apply(segmenter.append(chunk), to: &segments, in: &requests)
        }
        apply(segmenter.finish(), to: &segments, in: &requests)
        segments.open?.finish()
      } catch {
        segments.open?.finish(throwing: error)
        throw error
      }
      return try await joinedTexts(of: &requests)
    }
  }

  private func startRequest(index: Int, in requests: inout SegmentRequests) -> AsyncThrowingStream<Data, Error>.Continuation {
    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let transcribeSegment = transcribeSegment
    requests.addTask {
      (index, try await transcribeSegment(stream))
    }
    return continuation
  }

  private func apply(_ actions: [AudioSegmenter.Action], to segments: inout Segments, in requests: inout SegmentRequests) {
    for action in actions {
      switch action {
      case .audio(let chunk):
        openSegment(&segments, in: &requests).yield(chunk)
      case .cut:
        segments.open?.finish()
        segments.open = nil
      }
    }
  }

  /// The open segment, or a new one after a cut.
  private func openSegment(_ segments: inout Segments, in requests: inout SegmentRequests) -> AsyncThrowingStream<Data, Error>.Continuation {
    if let open = segments.open { return open }
    segments.latestIndex += 1
    let open = startRequest(index: segments.latestIndex, in: &requests)
    segments.open = open
    return open
  }

  private func joinedTexts(of requests: inout SegmentRequests) async throws -> String {
    var texts: [Int: String] = [:]
    for try await result in requests {
      texts[result.index] = result.text
    }
    return TranscriptJoiner.join(texts.sorted { $0.key < $1.key }.map(\.value), properNouns: properNouns)
  }
}
