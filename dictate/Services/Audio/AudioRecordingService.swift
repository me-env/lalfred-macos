import Foundation
import AVFoundation
import os

@MainActor
final class AudioRecordingService {
  enum RecordingError: LocalizedError {
    case microphonePermissionMissing
    case alreadyRecording
    case failedToCreateRecorder
    case notRecording

    var errorDescription: String? {
      switch self {
      case .microphonePermissionMissing:
        return "Microphone permission is not granted"
      case .alreadyRecording:
        return "A recording is already in progress"
      case .failedToCreateRecorder:
        return "No microphone device detected"
      case .notRecording:
        return "No active recording"
      }
    }
  }

  /// 16 kHz mono 16-bit little-endian PCM, the format ElevenLabs accepts as `pcm_s16le_16`.
  nonisolated static let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: true
  )!

  /// Audio kept after the stop request, so the end of the last word is not clipped.
  private static let trailingAudioDuration: TimeInterval = 0.05
  /// Ends the stream anyway if the device stops delivering audio before reaching the stop time.
  private static let stopFallbackDelay: TimeInterval = 1.0

  /// Created per recording and released after it: a live engine keeps the input device open,
  /// which holds Bluetooth headsets in their lower-quality headset (mic) mode.
  private var engine: AVAudioEngine?
  private var captureSession: AudioCaptureSession?

  var onAudioLevelUpdate: ((Float) -> Void)?

  private(set) var isRecording = false

  /// Starts capturing the microphone and returns a stream of PCM chunks as they are recorded.
  func startRecording() throws -> AsyncThrowingStream<Data, Error> {
    try ensureMicrophonePermission()
    try ensureNotRecording()

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
          let converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat) else {
      throw RecordingError.failedToCreateRecorder
    }
    converter.downmix = true

    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let session = AudioCaptureSession(
      converter: converter,
      continuation: continuation,
      onLevel: { [weak self] level in
        DispatchQueue.main.async { self?.onAudioLevelUpdate?(level) }
      }
    )

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: session.makeTapBlock())

    engine.prepare()
    do {
      try engine.start()
    } catch {
      inputNode.removeTap(onBus: 0)
      session.forceFinish(throwing: error)
      throw RecordingError.failedToCreateRecorder
    }

    self.engine = engine
    captureSession = session
    isRecording = true
    return stream
  }

  /// Keeps capturing until the audio recorded up to now has been delivered, then ends the stream.
  /// Returns the whole recording, in the same format as the streamed chunks.
  func stopRecording() async throws -> Data {
    guard isRecording, let captureSession else {
      throw RecordingError.notRecording
    }

    let stopHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.trailingAudioDuration)

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      captureSession.requestStop(atHostTime: stopHostTime) {
        continuation.resume()
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopFallbackDelay) {
        captureSession.forceFinish()
      }
    }

    stopEngine()
    return captureSession.recordedAudio
  }

  /// Stops capturing and ends the audio stream with an error, so consumers discard it.
  func cancelRecording() {
    guard isRecording else { return }

    captureSession?.forceFinish(throwing: CancellationError())
    stopEngine()
  }

  private func stopEngine() {
    guard isRecording else { return }

    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    captureSession = nil
    isRecording = false
  }

  private func ensureMicrophonePermission() throws {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    guard status == .authorized else {
      throw RecordingError.microphonePermissionMissing
    }
  }

  private func ensureNotRecording() throws {
    guard !isRecording else {
      throw RecordingError.alreadyRecording
    }
  }
}

/// Converts tap buffers and feeds the audio stream. Lives on the real-time audio thread, except for
/// `requestStop` and `forceFinish`, which the lock makes safe to call from the main thread.
private nonisolated final class AudioCaptureSession: @unchecked Sendable {
  private struct StopState {
    var stopHostTime: UInt64?
    var onFinish: (@Sendable () -> Void)?
    var isFinished = false
    var recordedAudio = Data()
  }

  private let converter: AVAudioConverter
  private let continuation: AsyncThrowingStream<Data, Error>.Continuation
  private let onLevel: @Sendable (Float) -> Void
  private let state = OSAllocatedUnfairLock(initialState: StopState())

  init(
    converter: AVAudioConverter,
    continuation: AsyncThrowingStream<Data, Error>.Continuation,
    onLevel: @escaping @Sendable (Float) -> Void
  ) {
    self.converter = converter
    self.continuation = continuation
    self.onLevel = onLevel
  }

  /// Every chunk sent to the stream so far.
  var recordedAudio: Data {
    state.withLock { $0.recordedAudio }
  }

  func makeTapBlock() -> AVAudioNodeTapBlock {
    { [self] buffer, time in
      process(buffer, at: time)
    }
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

  private func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
    onLevel(Self.normalizedLevel(of: buffer))

    let stopHostTime = state.withLock { $0.stopHostTime }
    let isLastBuffer = stopHostTime.map { Self.endHostTime(of: buffer, at: time) >= $0 } ?? false

    var convertedChunk = convert(buffer) ?? Data()
    if isLastBuffer {
      convertedChunk.append(drainConverter() ?? Data())
    }
    let chunk = convertedChunk

    // Yielding and finishing under the lock keeps `forceFinish` from ending the stream mid-chunk.
    let onFinish = state.withLock { state -> (@Sendable () -> Void)? in
      guard !state.isFinished else { return nil }
      if !chunk.isEmpty {
        continuation.yield(chunk)
        state.recordedAudio.append(chunk)
      }
      guard isLastBuffer else { return nil }
      state.isFinished = true
      continuation.finish()
      return state.onFinish
    }

    onFinish?()
  }

  private static func endHostTime(of buffer: AVAudioPCMBuffer, at time: AVAudioTime) -> UInt64 {
    // Without a host time, the first buffer after the stop request is the last one.
    guard time.isHostTimeValid else { return .max }
    let duration = Double(buffer.frameLength) / buffer.format.sampleRate
    return time.hostTime + AVAudioTime.hostTime(forSeconds: duration)
  }

  private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
    let outputFormat = AudioRecordingService.outputFormat
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16

    var didProvideInput = false
    return runConverter(capacity: capacity) { inputStatus in
      if didProvideInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      inputStatus.pointee = .haveData
      return buffer
    }
  }

  /// Returns the samples the resampler still holds once no more input will come.
  private func drainConverter() -> Data? {
    runConverter(capacity: 1024) { inputStatus in
      inputStatus.pointee = .endOfStream
      return nil
    }
  }

  private func runConverter(
    capacity: AVAudioFrameCount,
    input: @escaping (UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?
  ) -> Data? {
    let outputFormat = AudioRecordingService.outputFormat
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      return nil
    }

    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      input(inputStatus)
    }

    guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else {
      return nil
    }

    return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
  }

  private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }

    var sumOfSquares: Float = 0
    for index in 0..<Int(buffer.frameLength) {
      sumOfSquares += samples[index] * samples[index]
    }
    let rms = (sumOfSquares / Float(buffer.frameLength)).squareRoot()
    let averagePower = 20 * log10(max(rms, 1e-7))

    let minimumDecibels: Float = -50
    if averagePower <= minimumDecibels { return 0 }
    if averagePower >= 0 { return 1 }
    return (averagePower - minimumDecibels) / -minimumDecibels
  }
}
