import Foundation


/// Transcribes a recording as one request per segment, cut at pauses by `AudioSegmenter`, so earlier
/// segments are transcribed while the user still speaks. Texts are joined in recording order.
nonisolated struct SegmentedTranscriber {
  typealias SegmentTranscription = @Sendable (AsyncThrowingStream<Data, Error>) async throws -> String

  private struct Segment {
    let index: Int
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
  }

  private typealias SegmentRequests = ThrowingTaskGroup<(index: Int, text: String), Error>

  let transcribeSegment: SegmentTranscription
  let makeDetector: @Sendable () -> VoiceActivityDetecting?

  /// Throws the recording's error, or the first failed segment's; the other requests are then cancelled.
  @concurrent
  func transcribe(_ audio: AsyncThrowingStream<Data, Error>) async throws -> String {
    try await withThrowingTaskGroup(of: (index: Int, text: String).self) { requests in
      var segment = startSegment(index: 0, in: &requests)
      do {
        var segmenter = AudioSegmenter(makeDetector: makeDetector)
        for try await chunk in audio {
          segment = apply(segmenter.append(chunk), to: segment, in: &requests)
        }
        segment = apply(segmenter.finish(), to: segment, in: &requests)
        segment.continuation.finish()
      } catch {
        segment.continuation.finish(throwing: error)
        throw error
      }
      return try await joinedTexts(of: &requests)
    }
  }

  private func startSegment(index: Int, in requests: inout SegmentRequests) -> Segment {
    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let transcribeSegment = transcribeSegment
    requests.addTask {
      (index, try await transcribeSegment(stream))
    }
    return Segment(index: index, continuation: continuation)
  }

  /// Returns the segment receiving the audio after `actions`.
  private func apply(_ actions: [AudioSegmenter.Action], to segment: Segment, in requests: inout SegmentRequests) -> Segment {
    actions.reduce(segment) { segment, action in
      switch action {
      case .audio(let chunk):
        segment.continuation.yield(chunk)
        return segment
      case .cut:
        segment.continuation.finish()
        return startSegment(index: segment.index + 1, in: &requests)
      }
    }
  }

  private func joinedTexts(of requests: inout SegmentRequests) async throws -> String {
    var texts: [Int: String] = [:]
    for try await result in requests {
      texts[result.index] = result.text
    }
    return TranscriptJoiner.join(texts.sorted { $0.key < $1.key }.map(\.value))
  }
}
