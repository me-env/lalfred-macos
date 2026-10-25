import Foundation
import AVFoundation
import CoreAudio

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
    sampleRate: Double(TranscriptionAudio.sampleRate),
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

  private var deviceCapture: DeviceCapture?
  private let callbackQueue = DispatchQueue(label: "lalfred.audio-capture", qos: .userInteractive)
  private var captureSession: AudioCaptureSession?
  private lazy var deviceChangeObserver = AudioDeviceChangeObserver(queue: callbackQueue) { [weak self] in
    DispatchQueue.main.async {
      self?.scheduleDeviceChangeHandling()
    }
  }
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
    guard let inputDevice = AudioDevices.defaultInput() else {
      throw RecordingError.failedToCreateRecorder
    }
    let needsHeadsetSwitch = AudioDevices.needsHeadsetSwitch(inputDevice)

    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let session = makeCaptureSession(continuation: continuation)

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
    deviceChangeObserver.observe(inputDevice: inputDevice)

    isInputReady = !needsHeadsetSwitch
    if needsHeadsetSwitch {
      scheduleReadinessFallback(for: session)
    }
    return stream
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

  private func makeCaptureSession(continuation: AsyncThrowingStream<Data, Error>.Continuation) -> AudioCaptureSession {
    AudioCaptureSession(
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
  }

  private func stopCapture() {
    guard isRecording else { return }

    stopDeviceCapture()
    captureGeneration += 1
    captureSession = nil
    isRecording = false
  }

  private func stopDeviceCapture() {
    guard let deviceCapture else { return }
    deviceCapture.stop(on: callbackQueue)
    self.deviceCapture = nil
  }

  // MARK: - Input readiness

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

  /// Several properties change together; they are handled once.
  private func scheduleDeviceChangeHandling() {
    guard captureSession != nil, !isDeviceChangeHandlingScheduled else { return }
    isDeviceChangeHandlingScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isDeviceChangeHandlingScheduled = false
      self.handleDeviceChange()
    }
  }

  /// A Bluetooth headset's own mode switch needs nothing from us: the system stops and restarts the
  /// device's I/O around it. Only a different input device, or a different input format, needs a
  /// new capture. Listeners outlive recordings and watch every device used so far, so the change may
  /// concern neither the current recording nor its device.
  private func handleDeviceChange() {
    guard isRecording, let session = captureSession, let deviceCapture else { return }

    let currentInput = AudioDevices.defaultInput()
    let deviceChanged = currentInput != deviceCapture.device
    let formatChanged = !deviceChanged && !deviceCapture.matchesCurrentFormat()

    guard deviceChanged || formatChanged, captureRestarts < Self.maxCaptureRestarts else { return }
    restartCapture(for: session, inputDevice: currentInput)
  }

  private func restartCapture(for session: AudioCaptureSession, inputDevice newInput: AudioDeviceID?) {
    captureRestarts += 1
    captureGeneration += 1
    stopDeviceCapture()

    // After the old capture's last callback, so it cannot count as the new capture's first sound.
    callbackQueue.async {
      session.resetSoundDetection()
    }

    guard let newInput,
          let capture = try? DeviceCapture(device: newInput, session: session, queue: callbackQueue) else {
      // Ends the recording with an error rather than silently capturing nothing.
      session.forceFinish(throwing: RecordingError.failedToCreateRecorder)
      return
    }

    deviceCapture = capture
    deviceChangeObserver.observe(inputDevice: newInput)
    updateInputReadiness(after: newInput, for: session)
  }

  private func updateInputReadiness(after newInput: AudioDeviceID, for session: AudioCaptureSession) {
    guard AudioDevices.needsHeadsetSwitch(newInput) else { return }
    if isInputReady {
      isInputReady = false
      onInputReadinessChange?(false)
    }
    scheduleReadinessFallback(for: session)
  }

  // MARK: - Preconditions

  private func ensureMicrophonePermission() throws {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      throw RecordingError.microphonePermissionMissing
    }
  }

  private func ensureNotRecording() throws {
    guard !isRecording else {
      throw RecordingError.alreadyRecording
    }
  }
}
