import Foundation
import AVFoundation
import CoreAudio
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

  /// Ends the stream anyway if the device stops delivering audio before reaching the stop time.
  private static let stopFallbackDelay: TimeInterval = 1.0
  /// A Bluetooth headset switching from music to headset mode delivers pure silence until its mic
  /// is live, measured at ~0.97 s. Its noise gate also sends silence while the user is quiet, so the
  /// input counts as ready on the first sound or after this delay, whichever comes first.
  private static let inputReadyFallbackDelay: TimeInterval = 1.2
  /// Guards against a device that keeps changing; each restart reopens the microphone.
  private static let maxCaptureRestarts = 3

  /// Captures straight from the input device with a HAL IOProc. `AVAudioEngine` opened a playback
  /// stream that collided with a Bluetooth headset's mode switch, and audio queues kept the mic
  /// running for seconds after being disposed, which jammed a recording started in that window.
  /// The IOProc starts and stops the device immediately, so the mic is released between recordings.
  private var deviceCapture: DeviceCapture?
  private let callbackQueue = DispatchQueue(label: "lalfred.audio-capture", qos: .userInteractive)
  private var captureSession: AudioCaptureSession?
  private var deviceListeners: [DeviceListener] = []
  private var isDeviceChangeHandlingScheduled = false
  private var captureRestarts = 0
  /// Bumped on every (re)start, so a readiness fallback from an earlier capture is ignored.
  private var captureGeneration = 0

  var onAudioLevelUpdate: ((Float) -> Void)?
  var onInputReadinessChange: ((Bool) -> Void)?

  private(set) var isRecording = false
  /// False while a Bluetooth headset switches to its mic mode; level updates are held back until then.
  private(set) var isInputReady = false

  /// Starts capturing the microphone and returns a stream of PCM chunks as they are recorded.
  func startRecording() throws -> AsyncThrowingStream<Data, Error> {
    try ensureMicrophonePermission()
    try ensureNotRecording()
    let inputDevice = try Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
    let needsHeadsetSwitch = Self.needsHeadsetSwitch(inputDevice)

    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let session = AudioCaptureSession(
      continuation: continuation,
      onLevel: { [weak self] level in
        DispatchQueue.main.async {
          guard let self, self.isInputReady else { return }
          self.onAudioLevelUpdate?(level)
        }
      },
      onSound: { [weak self] session in
        DispatchQueue.main.async {
          self?.markInputReady(for: session)
        }
      }
    )

    do {
      deviceCapture = try DeviceCapture(device: inputDevice, session: session, queue: callbackQueue)
    } catch {
      session.forceFinish(throwing: error)
      throw error
    }

    captureSession = session
    isRecording = true
    captureRestarts = 0
    captureGeneration += 1
    observeDevices(of: inputDevice, session: session)

    isInputReady = !needsHeadsetSwitch
    if needsHeadsetSwitch {
      scheduleReadinessFallback(for: session)
    }
    return stream
  }

  private func stopDeviceCapture() {
    guard let deviceCapture else { return }
    deviceCapture.stop(on: callbackQueue)
    self.deviceCapture = nil
  }

  private func scheduleReadinessFallback(for session: AudioCaptureSession) {
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.inputReadyFallbackDelay) { [weak self] in
      guard let self, self.captureGeneration == generation else { return }
      self.markInputReady(for: session)
    }
  }

  private func markInputReady(for session: AudioCaptureSession) {
    guard captureSession === session, !isInputReady else { return }
    isInputReady = true
    onInputReadinessChange?(true)
  }

  // MARK: - Input device changes

  /// A Bluetooth headset's own mode switch needs nothing from us: the system stops and restarts the
  /// device's I/O around it. Only a different input device, or a different input format, needs a
  /// new capture.
  private func observeDevices(of inputDevice: AudioDeviceID, session: AudioCaptureSession) {
    let onChange: @Sendable () -> Void = { [weak self] in
      DispatchQueue.main.async {
        self?.scheduleDeviceChangeHandling(for: session)
      }
    }

    addDeviceListener(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, onChange: onChange)
    addDeviceListener(inputDevice, kAudioDevicePropertyNominalSampleRate, onChange: onChange)
    addDeviceListener(inputDevice, kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput, onChange: onChange)
  }

  private func addDeviceListener(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    onChange: @escaping @Sendable () -> Void
  ) {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    let block = Self.makeListenerBlock(onChange)
    guard AudioObjectAddPropertyListenerBlock(objectID, &address, callbackQueue, block) == noErr else { return }
    deviceListeners.append(DeviceListener(objectID: objectID, address: address, block: block))
  }

  private nonisolated static func makeListenerBlock(_ onChange: @escaping @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
    { _, _ in onChange() }
  }

  private func removeDeviceListeners() {
    for var listener in deviceListeners {
      AudioObjectRemovePropertyListenerBlock(listener.objectID, &listener.address, callbackQueue, listener.block)
    }
    deviceListeners.removeAll()
  }

  /// Several properties change together; they are handled once.
  private func scheduleDeviceChangeHandling(for session: AudioCaptureSession) {
    guard captureSession === session, !isDeviceChangeHandlingScheduled else { return }
    isDeviceChangeHandlingScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isDeviceChangeHandlingScheduled = false
      self.handleDeviceChange(for: session)
    }
  }

  private func handleDeviceChange(for session: AudioCaptureSession) {
    guard captureSession === session, isRecording, let deviceCapture else { return }

    let currentInput = (try? Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)) ?? AudioDeviceID(kAudioObjectUnknown)
    let deviceChanged = currentInput != deviceCapture.device
    let formatChanged = !deviceChanged && !deviceCapture.matchesCurrentFormat()

    guard deviceChanged || formatChanged, captureRestarts < Self.maxCaptureRestarts else { return }
    restartCapture(for: session, inputDevice: currentInput)
  }

  private func restartCapture(for session: AudioCaptureSession, inputDevice newInput: AudioDeviceID) {
    captureRestarts += 1
    captureGeneration += 1
    stopDeviceCapture()
    removeDeviceListeners()

    // After the old capture's last callback, so it cannot count as the new capture's first sound.
    callbackQueue.async {
      session.resetSoundDetection()
    }

    guard newInput != kAudioObjectUnknown,
          let capture = try? DeviceCapture(device: newInput, session: session, queue: callbackQueue) else {
      // Ends the recording with an error rather than silently capturing nothing.
      session.forceFinish(throwing: RecordingError.failedToCreateRecorder)
      return
    }

    deviceCapture = capture
    observeDevices(of: newInput, session: session)

    let needsHeadsetSwitch = Self.needsHeadsetSwitch(newInput)
    if isInputReady, needsHeadsetSwitch {
      isInputReady = false
      onInputReadinessChange?(false)
    }
    if needsHeadsetSwitch {
      scheduleReadinessFallback(for: session)
    }
  }

  /// Keeps capturing until the audio recorded up to now has been delivered, then ends the stream.
  /// Returns the whole recording, in the same format as the streamed chunks.
  func stopRecording() async throws -> Data {
    guard isRecording, let captureSession else {
      throw RecordingError.notRecording
    }

    let stopHostTime = mach_absolute_time()

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      captureSession.requestStop(atHostTime: stopHostTime) {
        continuation.resume()
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopFallbackDelay) {
        captureSession.forceFinish()
      }
    }

    stopCapture()
    return captureSession.recordedAudio
  }

  /// Stops capturing and ends the audio stream with an error, so consumers discard it.
  func cancelRecording() {
    guard isRecording else { return }

    captureSession?.forceFinish(throwing: CancellationError())
    stopCapture()
  }

  private func stopCapture() {
    guard isRecording else { return }

    stopDeviceCapture()
    removeDeviceListeners()
    captureGeneration += 1
    captureSession = nil
    isRecording = false
  }

  private func ensureMicrophonePermission() throws {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    guard status == .authorized else {
      throw RecordingError.microphonePermissionMissing
    }
  }

  private static func defaultDevice(_ selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    let status = readProperty(AudioObjectID(kAudioObjectSystemObject), selector, into: &deviceID)
    guard status == noErr, deviceID != kAudioObjectUnknown else {
      throw RecordingError.failedToCreateRecorder
    }
    return deviceID
  }

  private static func nominalSampleRate(of device: AudioDeviceID) -> Float64 {
    var sampleRate: Float64 = 0
    _ = readProperty(device, kAudioDevicePropertyNominalSampleRate, into: &sampleRate)
    return sampleRate
  }

  private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
    var transportType: UInt32 = 0
    return readProperty(device, kAudioDevicePropertyTransportType, into: &transportType) == noErr
      && transportType == kAudioDeviceTransportTypeBluetooth
  }

  /// A Bluetooth headset whose mic no app is using, and whose playback still runs at a music-mode
  /// sample rate, has to switch to headset mode before its mic delivers audio. Right after a
  /// recording the headset is still in headset mode (same rate as the mic) and needs no switch.
  private static func needsHeadsetSwitch(_ inputDevice: AudioDeviceID) -> Bool {
    var isRunningSomewhere: UInt32 = 0
    guard isBluetooth(inputDevice),
          readProperty(inputDevice, kAudioDevicePropertyDeviceIsRunningSomewhere, into: &isRunningSomewhere) == noErr,
          isRunningSomewhere == 0,
          let outputDevice = try? defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else {
      return false
    }
    return nominalSampleRate(of: outputDevice) != nominalSampleRate(of: inputDevice)
  }

  private static func readProperty<Value: BitwiseCopyable>(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    into value: inout Value
  ) -> OSStatus {
    var size = UInt32(MemoryLayout<Value>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
  }

  private func ensureNotRecording() throws {
    guard !isRecording else {
      throw RecordingError.alreadyRecording
    }
  }
}

/// One IOProc on one input device, delivering its buffers to the capture session.
private nonisolated final class DeviceCapture: @unchecked Sendable {
  let device: AudioDeviceID
  private let format: AVAudioFormat
  private var procID: AudioDeviceIOProcID?

  init(device: AudioDeviceID, session: AudioCaptureSession, queue: DispatchQueue) throws {
    guard let format = Self.inputFormat(of: device),
          let converter = AVAudioConverter(from: format, to: AudioRecordingService.outputFormat) else {
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    converter.downmix = true
    self.device = device
    self.format = format

    var procID: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { _, inputData, inputTime, _, _ in
      session.process(inputData, inputTime: inputTime.pointee, format: format, converter: converter)
    }
    guard status == noErr, let procID else {
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    guard AudioDeviceStart(device, procID) == noErr else {
      AudioDeviceDestroyIOProcID(device, procID)
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    self.procID = procID
  }

  func matchesCurrentFormat() -> Bool {
    guard let current = Self.inputFormat(of: device) else { return false }
    return current.sampleRate == format.sampleRate
      && current.channelCount == format.channelCount
      && current.commonFormat == format.commonFormat
      && current.isInterleaved == format.isInterleaved
  }

  /// Stops the device right away; the IOProc is destroyed on `queue`, after any callback already
  /// scheduled there has run.
  func stop(on queue: DispatchQueue) {
    guard let procID else { return }
    AudioDeviceStop(device, procID)
    let device = device
    nonisolated(unsafe) let stoppedProcID = procID
    queue.async {
      AudioDeviceDestroyIOProcID(device, stoppedProcID)
    }
    self.procID = nil
  }

  /// The format of the device's first input stream, as the IOProc receives it. For a stream with
  /// separate channel buffers, only the first channel is used.
  private static func inputFormat(of device: AudioDeviceID) -> AVAudioFormat? {
    var streamsAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var stream = AudioStreamID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioStreamID>.size)
    guard AudioObjectGetPropertyData(device, &streamsAddress, 0, nil, &size, &stream) == noErr,
          stream != kAudioObjectUnknown else {
      return nil
    }

    var formatAddress = AudioObjectPropertyAddress(
      mSelector: kAudioStreamPropertyVirtualFormat,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var description = AudioStreamBasicDescription()
    size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &size, &description) == noErr,
          description.mSampleRate > 0, description.mChannelsPerFrame > 0,
          let format = AVAudioFormat(streamDescription: &description) else {
      return nil
    }

    guard !format.isInterleaved, format.channelCount > 1 else { return format }
    return AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate, channels: 1, interleaved: false)
  }
}

private struct DeviceListener {
  let objectID: AudioObjectID
  var address: AudioObjectPropertyAddress
  let block: AudioObjectPropertyListenerBlock
}

/// Feeds the audio stream from the capture callbacks. Runs on the capture callback queue, except for
/// `requestStop` and `forceFinish`, which the lock makes safe to call from the main thread.
private nonisolated final class AudioCaptureSession: @unchecked Sendable {
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
  /// 50 ms of 16 kHz 16-bit audio.
  private static let minimumChunkByteCount = 1_600

  /// Touched only on the capture callback queue.
  private var hasDeliveredSound = false
  private var pendingChunk = Data()

  init(
    continuation: AsyncThrowingStream<Data, Error>.Continuation,
    onLevel: @escaping @Sendable (Float) -> Void,
    onSound: @escaping @Sendable (AudioCaptureSession) -> Void
  ) {
    self.continuation = continuation
    self.onLevel = onLevel
    self.onSound = onSound
  }

  /// Called on the capture callback queue, between two captures of the same recording.
  func resetSoundDetection() {
    hasDeliveredSound = false
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
    format: AVAudioFormat,
    converter: AVAudioConverter
  ) {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    guard let firstBuffer = buffers.first, firstBuffer.mData != nil, firstBuffer.mDataByteSize > 0 else { return }

    var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: firstBuffer)
    let converted: (chunk: Data, frameCount: Int)? = withUnsafePointer(to: &bufferList) { listPointer in
      guard let input = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: listPointer) else { return nil }
      return (Self.convert(input, with: converter) ?? Data(), Int(input.frameLength))
    }
    guard let converted else { return }

    let stopHostTime = state.withLock { $0.stopHostTime }
    let isLastBuffer = stopHostTime.map {
      Self.endHostTime(of: converted.frameCount, sampleRate: format.sampleRate, startingAt: inputTime) >= $0
    } ?? false

    var chunk = converted.chunk
    if isLastBuffer {
      chunk.append(Self.drain(converter) ?? Data())
    }

    chunk.withUnsafeBytes { rawBuffer in
      let samples = rawBuffer.bindMemory(to: Int16.self)
      onLevel(Self.normalizedLevel(of: samples))
      // Headsets send pure digital silence until their mic is live, so the first sound marks it ready.
      if !hasDeliveredSound, samples.contains(where: { $0 != 0 }) {
        hasDeliveredSound = true
        onSound(self)
      }
    }

    // Devices deliver small buffers (20 ms for a headset); they are sent in larger chunks.
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

  private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> Data? {
    let ratio = AudioRecordingService.outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16

    var didProvideInput = false
    return run(converter, capacity: capacity) { inputStatus in
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
  private static func drain(_ converter: AVAudioConverter) -> Data? {
    run(converter, capacity: 1024) { inputStatus in
      inputStatus.pointee = .endOfStream
      return nil
    }
  }

  private static func run(
    _ converter: AVAudioConverter,
    capacity: AVAudioFrameCount,
    input: @escaping (UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?
  ) -> Data? {
    guard let output = AVAudioPCMBuffer(pcmFormat: AudioRecordingService.outputFormat, frameCapacity: capacity) else {
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

  private static func normalizedLevel(of samples: UnsafeBufferPointer<Int16>) -> Float {
    guard !samples.isEmpty else { return 0 }

    var sumOfSquares: Float = 0
    for sample in samples {
      let value = Float(sample) / Float(Int16.max)
      sumOfSquares += value * value
    }
    let rms = (sumOfSquares / Float(samples.count)).squareRoot()
    let averagePower = 20 * log10(max(rms, 1e-7))

    let minimumDecibels: Float = -50
    if averagePower <= minimumDecibels { return 0 }
    if averagePower >= 0 { return 1 }
    return (averagePower - minimumDecibels) / -minimumDecibels
  }
}
