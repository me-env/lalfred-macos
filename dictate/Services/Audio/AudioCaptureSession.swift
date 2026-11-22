import AVFoundation
import os

/// Feeds the audio stream from the capture callbacks. Runs on the capture callback queue, except for
/// `requestStop`, `forceFinish`, `beginCapture` and `activity`, which locks make safe to call from
/// the main thread.
nonisolated final class AudioCaptureSession: @unchecked Sendable {
  /// The device capture whose buffers are accepted, and what it delivered.
  private struct CaptureState {
    var generation = 0
    var activity = CaptureActivity(startTime: 0)
  }

  private struct StopState {
    var stopHostTime: UInt64?
    var onFinish: (@Sendable () -> Void)?
    var isFinished = false
    var recordedAudio = Data()
  }

  private let continuation: AsyncThrowingStream<Data, Error>.Continuation
  private let onLevel: @Sendable (Float) -> Void
  private let onSound: @Sendable (AudioCaptureSession) -> Void
  private let state = OSAllocatedUnfairLock(initialState: StopState())
  private let capture = OSAllocatedUnfairLock(initialState: CaptureState())
  /// 50 ms of 16 kHz 16-bit audio.
  private static let minimumChunkByteCount = 1_600

  /// Touched only on the capture callback queue.
  private var pendingChunk = Data()
  private var levelMeter = AudioLevelMeter()

  init(
    continuation: AsyncThrowingStream<Data, Error>.Continuation,
    onLevel: @escaping @Sendable (Float) -> Void,
    onSound: @escaping @Sendable (AudioCaptureSession) -> Void
  ) {
    self.continuation = continuation
    self.onLevel = onLevel
    self.onSound = onSound
  }

  /// Seconds on the clock `CaptureActivity` uses.
  static func now() -> TimeInterval {
    AVAudioTime.seconds(forHostTime: mach_absolute_time())
  }

  /// Accepts only `generation`'s buffers from now on, so a late callback of a stopped capture can
  /// neither add audio nor count as the new capture's first callback or first sound.
  func beginCapture(generation: Int) {
    capture.withLock { state in
      state.generation = generation
      state.activity = CaptureActivity(startTime: Self.now())
    }
  }

  var activity: CaptureActivity {
    capture.withLock { $0.activity }
  }

  /// Every chunk sent to the stream so far.
  var recordedAudio: Data {
    state.withLock { $0.recordedAudio }
  }

  /// The stream ends with the first buffer that reaches `hostTime`; `onFinish` is then called once.
  func requestStop(atHostTime hostTime: UInt64, onFinish: @escaping @Sendable () -> Void) {
    let alreadyFinished = state.withLock { state in
      state.stopHostTime = hostTime
      state.onFinish = onFinish
      return state.isFinished
    }

    if alreadyFinished {
      onFinish()
    }
  }

  /// Ends the stream immediately, normally or with `error`. Has no effect once the stream ended.
  func forceFinish(throwing error: Error? = nil) {
    let onFinish = state.withLock { state -> (@Sendable () -> Void)? in
      guard !state.isFinished else { return nil }
      state.isFinished = true
      continuation.finish(throwing: error)
      return state.onFinish
    }

    onFinish?()
  }

  /// `inputData` is the device's buffer list; only its first buffer, described by `format`, is used.
  func process(
    _ inputData: UnsafePointer<AudioBufferList>,
    inputTime: AudioTimeStamp,
    generation: Int,
    format: AVAudioFormat,
    converter: AVAudioConverter
  ) {
    guard recordCallback(of: generation) else { return }
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    guard let firstBuffer = buffers.first, firstBuffer.mData != nil, firstBuffer.mDataByteSize > 0 else { return }

    var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: firstBuffer)
    let converted: (chunk: Data, frameCount: Int)? = withUnsafePointer(to: &bufferList) { listPointer in
      guard let input = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: listPointer) else { return nil }
      return (AudioConversion.convert(input, with: converter) ?? Data(), Int(input.frameLength))
    }
    guard let converted else { return }

    let stopHostTime = state.withLock { $0.stopHostTime }
    let isLastBuffer = stopHostTime.map {
      Self.endHostTime(of: converted.frameCount, sampleRate: format.sampleRate, startingAt: inputTime) >= $0
    } ?? false

    var chunk = converted.chunk
    if isLastBuffer {
      chunk.append(AudioConversion.drain(converter) ?? Data())
    }

    inspect(chunk)
    send(chunk, isLastBuffer: isLastBuffer)
  }

  /// Returns whether the buffer belongs to the current capture, and notes its arrival if so.
  private func recordCallback(of generation: Int) -> Bool {
    capture.withLock { state in
      guard state.generation == generation else { return false }
      state.activity.lastCallbackTime = Self.now()
      return true
    }
  }

  /// Reports the level, and the first sound: headsets send pure digital silence until their mic is live.
  private func inspect(_ chunk: Data) {
    guard !chunk.isEmpty else { return }
    let hasSound = chunk.withUnsafeBytes { rawBuffer in
      let samples = rawBuffer.bindMemory(to: Int16.self)
      if let level = levelMeter.levelToReport(for: samples) {
        onLevel(level)
      }
      return samples.contains { $0 != 0 }
    }
    if recordSound(hasSound) {
      onSound(self)
    }
  }

  /// Tracks runs of exact zeros; returns true for the capture's first buffer holding sound.
  private func recordSound(_ hasSound: Bool) -> Bool {
    capture.withLock { state in
      guard hasSound else {
        state.activity.zeroRunStartTime = state.activity.zeroRunStartTime ?? Self.now()
        return false
      }
      state.activity.zeroRunStartTime = nil
      guard !state.activity.hasDeliveredSound else { return false }
      state.activity.hasDeliveredSound = true
      return true
    }
  }

  /// Devices deliver small buffers (20 ms for a headset); they are sent in larger chunks.
  private func send(_ chunk: Data, isLastBuffer: Bool) {
    pendingChunk.append(chunk)
    guard isLastBuffer || pendingChunk.count >= Self.minimumChunkByteCount else { return }
    let outgoing = pendingChunk
    pendingChunk = Data()

    // Yielding and finishing under the lock keeps `forceFinish` from ending the stream mid-chunk.
    let onFinish = state.withLock { state -> (@Sendable () -> Void)? in
      guard !state.isFinished else { return nil }
      if !outgoing.isEmpty {
        continuation.yield(outgoing)
        state.recordedAudio.append(outgoing)
      }
      guard isLastBuffer else { return nil }
      state.isFinished = true
      continuation.finish()
      return state.onFinish
    }

    onFinish?()
  }

  private static func endHostTime(of frameCount: Int, sampleRate: Double, startingAt startTime: AudioTimeStamp) -> UInt64 {
    // Without a host time, the first buffer after the stop request is the last one.
    guard startTime.mFlags.contains(.hostTimeValid) else { return .max }
    return startTime.mHostTime + AVAudioTime.hostTime(forSeconds: Double(frameCount) / sampleRate)
  }
}
