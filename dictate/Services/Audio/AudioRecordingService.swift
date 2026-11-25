import Foundation
import AVFoundation
import CoreAudio
import os

private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "Audio")

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
  /// input counts as live on the first sound or after this delay, whichever comes first.
  private static let inputLiveFallbackDelay: TimeInterval = 1.2
  /// One Bluetooth connection fires several properties over 1–2 s, and starting a capture can fire
  /// them too; they are handled once things settle.
  private static let deviceChangeDebounce: TimeInterval = 0.3
  private static let watchdogInterval: TimeInterval = 0.5

  private var deviceCapture: DeviceCapture?
  /// The microphone of the running capture; nil once recovery gave up.
  private var activeMicrophone: InputDevice?
  private let callbackQueue = DispatchQueue(label: "lalfred.audio-capture", qos: .userInteractive)
  private var captureSession: AudioCaptureSession?
  private lazy var deviceChangeObserver = AudioDeviceChangeObserver(queue: callbackQueue) { [weak self] in
    DispatchQueue.main.async {
      self?.scheduleDeviceChangeHandling()
    }
  }
  private let preferencesStore = MicrophonePreferencesStore()
  private var pendingDeviceChange: DispatchWorkItem?
  private var watchdogTimer: Timer?
  private var recoveryBudget = CaptureRecoveryBudget()
  /// Bumped on every (re)start, so buffers and fallbacks of an earlier capture are ignored.
  private var captureGeneration = 0
  private var hasSignaledInputLive = false

  var onAudioLevelUpdate: ((Float) -> Void)?
  var onInputReadinessChange: ((Bool) -> Void)?
  var onInputLive: (() -> Void)?
  var onCaptureLost: (() -> Void)?

  private(set) var isRecording = false
  /// False while a Bluetooth headset switches to its mic mode; level updates are held back until then.
  private(set) var isInputReady = false

  /// Starts capturing the microphone and returns a stream of PCM chunks as they are recorded.
  func startRecording() throws -> AsyncThrowingStream<Data, Error> {
    try ensureMicrophonePermission()
    try ensureNotRecording()
    guard let microphone = selectMicrophone(excluding: []) else {
      throw RecordingError.failedToCreateRecorder
    }

    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let session = makeCaptureSession(continuation: continuation)

    do {
      try startCapture(on: microphone, for: session)
    } catch {
      activeMicrophone = nil
      session.forceFinish(throwing: error)
      throw error
    }

    captureSession = session
    isRecording = true
    recoveryBudget = CaptureRecoveryBudget()
    hasSignaledInputLive = false
    startWatchdog()
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
          self?.markInputLive(for: session)
        }
      }
    )
  }

  private func selectMicrophone(excluding excludedUIDs: Set<String>) -> InputDevice? {
    MicrophoneSelector.select(in: MicrophoneSelector.Context(
      devices: AudioDevices.inputDevices(),
      systemDefault: AudioDevices.defaultInput(),
      preferences: preferencesStore.load(),
      isLidClosed: ClamshellState.isLidClosed(),
      excludedUIDs: excludedUIDs
    ))
  }

  /// Starts a new device capture of `microphone`, whose buffers are the only ones `session` accepts.
  private func startCapture(on microphone: InputDevice, for session: AudioCaptureSession) throws {
    captureGeneration += 1
    activeMicrophone = microphone
    session.beginCapture(generation: captureGeneration)
    AudioDevices.clearInputMute(microphone.id)
    // Read before starting: the capture itself makes the device run.
    let needsHeadsetSwitch = AudioDevices.needsHeadsetSwitch(microphone.id)

    deviceCapture = try DeviceCapture(device: microphone.id, generation: captureGeneration, session: session, queue: callbackQueue)
    deviceChangeObserver.observe(inputDevice: microphone.id)
    setInputReady(!needsHeadsetSwitch)
    scheduleInputLiveFallback(for: session)
    logger.info("Capturing from \(microphone.name, privacy: .public) (\(String(describing: microphone.transport), privacy: .public))")
  }

  private func stopCapture() {
    guard isRecording else { return }

    stopDeviceCapture()
    stopWatchdog()
    pendingDeviceChange?.cancel()
    pendingDeviceChange = nil
    activeMicrophone = nil
    captureGeneration += 1
    captureSession = nil
    isRecording = false
    // Every recording starts from the same readiness, whatever the previous one ended with.
    isInputReady = false
  }

  private func stopDeviceCapture() {
    guard let deviceCapture else { return }
    deviceCapture.stop(on: callbackQueue)
    self.deviceCapture = nil
  }

  // MARK: - Input readiness

  private func scheduleInputLiveFallback(for session: AudioCaptureSession) {
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.inputLiveFallbackDelay) { [weak self] in
      guard let self, self.captureGeneration == generation else { return }
      self.markInputLive(for: session)
    }
  }

  private func markInputLive(for session: AudioCaptureSession) {
    guard captureSession === session else { return }
    setInputReady(true)
    guard !hasSignaledInputLive else { return }
    hasSignaledInputLive = true
    notify { $0.onInputLive?() }
  }

  private func setInputReady(_ isReady: Bool) {
    guard isInputReady != isReady else { return }
    isInputReady = isReady
    notify { $0.onInputReadinessChange?(isReady) }
  }

  /// Callbacks run on their own main-queue turn, never inside a call into this service, so the
  /// owner is never re-entered while it is changing its own state.
  private func notify(_ deliver: @escaping (AudioRecordingService) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      deliver(self)
    }
  }

  // MARK: - Disruptions and recovery

  /// Listeners outlive recordings and watch every device used so far, so the change may concern
  /// neither the current recording nor its microphone.
  private func scheduleDeviceChangeHandling() {
    guard isRecording else { return }
    pendingDeviceChange?.cancel()
    let handling = DispatchWorkItem { [weak self] in
      self?.handleDeviceChange()
    }
    pendingDeviceChange = handling
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.deviceChangeDebounce, execute: handling)
  }

  private func handleDeviceChange() {
    pendingDeviceChange = nil
    guard isRecording, let activeMicrophone, let deviceCapture else { return }
    let disruption = CaptureDisruption.detect(
      activeUID: activeMicrophone.uid,
      in: AudioDevices.inputDevices(),
      formatMatches: deviceCapture.matchesCurrentFormat()
    )
    guard let disruption else { return }
    recover(from: disruption)
  }

  private func startWatchdog() {
    watchdogTimer = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.checkCaptureHealth()
      }
    }
  }

  private func stopWatchdog() {
    watchdogTimer?.invalidate()
    watchdogTimer = nil
  }

  /// Device changes waiting to be handled are left to `handleDeviceChange`, as they likely explain
  /// what the watchdog sees.
  private func checkCaptureHealth() {
    guard pendingDeviceChange == nil, let captureSession, let activeMicrophone, deviceCapture != nil else { return }
    let disruption = CaptureWatchdog.verdict(
      for: captureSession.activity,
      at: AudioCaptureSession.now(),
      isInternalMic: activeMicrophone.isInternalMic
    )
    guard let disruption else { return }
    recover(from: disruption)
  }

  /// Rebuilds the capture on the microphone the recovery budget picks, or ends the recording with
  /// the audio captured so far.
  private func recover(from disruption: CaptureDisruption) {
    guard let session = captureSession, let failedMicrophone = activeMicrophone else { return }
    let nextMicrophone = recoveryBudget.nextMicrophone(after: disruption, on: failedMicrophone) { excludedUIDs in
      selectMicrophone(excluding: excludedUIDs)
    }
    logger.notice("\(String(describing: disruption), privacy: .public) on \(failedMicrophone.name, privacy: .public), next: \(nextMicrophone?.name ?? "none", privacy: .public)")
    stopDeviceCapture()

    guard let nextMicrophone else {
      giveUp(on: session)
      return
    }
    do {
      try startCapture(on: nextMicrophone, for: session)
    } catch {
      recover(from: .deviceLost)
    }
  }

  private func giveUp(on session: AudioCaptureSession) {
    activeMicrophone = nil
    stopWatchdog()
    session.forceFinish()
    notify { $0.onCaptureLost?() }
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
