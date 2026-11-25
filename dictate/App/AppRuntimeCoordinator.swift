import SwiftUI
import Carbon.HIToolbox


@MainActor
final class AppRuntimeCoordinator {
  private let shortcuts: Shortcuts
  private let indicator: IndicatorPresenting
  private let pasteService: PastingAtCursor
  private let recordingService: AudioRecordingServicing
  private let lastRecording = LastRecordingStore()

  private(set) var sessionState = DictationSessionStateMachine()
  private var pendingTranscription: Task<String, Error>?
  private var processingTask: Task<Void, Never>?
  private var processingStartDate: Date = .distantPast
  /// Presses sooner than this after processing starts are ignored, so a double press doesn't throw away the dictation.
  private let minimumProcessingCancelDelay: TimeInterval = 0.5
  private var hasPlayedStartSound = false
  private var wasCaptureLost = false

  private var toggleRecordingMonitor: UnifiedShortcutMonitor?
  private var holdToSpeakMonitor: UnifiedShortcutMonitor?
  private var retryLastRecordingMonitor: UnifiedShortcutMonitor?
  private var escapeHotKeyMonitor: CarbonHotKeyMonitor?

  private var shortcutCaptureObserver: NSObjectProtocol?
#if DEBUG
  private var debugCommandObserver: NSObjectProtocol?
#endif
  private var isShortcutCaptureActive = false
  private var isHoldToSpeakActive = false
  private var lastPressDate: Date = .distantPast
  private let minimumPressInterval: TimeInterval = 0.30

  private lazy var listeningFlow = ListeningFlowHandler(
    recordingService: recordingService,
    indicator: indicator,
    activateListeningHotKeys: { [weak self] in
      self?.activateListeningHotKeys()
    },
    deactivateListeningHotKeys: { [weak self] in
      self?.deactivateListeningHotKeys()
    }
  )

  private lazy var processingFlowHandler = ProcessingFlowHandler(
    recordingService: recordingService,
    lastRecording: lastRecording,
    pasteService: pasteService,
    indicator: indicator,
    deactivateListeningHotKeys: { [weak self] in
      self?.deactivateListeningHotKeys()
    }
  )

  init(
    shortcuts: Shortcuts,
    indicator: IndicatorPresenting? = nil,
    pasteService: PastingAtCursor? = nil,
    recordingService: AudioRecordingServicing? = nil,
  ) {
    self.shortcuts = shortcuts
    self.indicator = indicator ?? IndicatorPanelController()
    self.pasteService = pasteService ?? PasteAtCursorService()
    self.recordingService = recordingService ?? AudioRecordingService()
    registerRecordingServiceCallbacks()
  }

  deinit {
    if let shortcutCaptureObserver {
      NotificationCenter.default.removeObserver(shortcutCaptureObserver)
    }
#if DEBUG
    if let debugCommandObserver {
      NotificationCenter.default.removeObserver(debugCommandObserver)
    }
#endif
  }

  /// Never mutate `sessionState` across a call into a service, not even through `inout`: a service
  /// call can reach these callbacks, which read it, and Swift aborts on the overlapping access.
  private func registerRecordingServiceCallbacks() {
    recordingService.onAudioLevelUpdate = { [weak self] level in
      guard let self, self.sessionState.isListening else { return }
      self.indicator.updateListeningLevel(CGFloat(level))
    }

    recordingService.onInputReadinessChange = { [weak self] isReady in
      guard let self, self.sessionState.isListening else { return }
      if isReady {
        self.indicator.showListening()
      } else {
        self.indicator.showPreparing()
      }
    }

    // During a headset switch the sound fails to play and blocks the main thread, and playing on
    // the headset while its mic starts can drop the mic link, so it waits for audio to flow.
    recordingService.onInputLive = { [weak self] in
      guard let self, self.sessionState.isListening else { return }
      self.playStartSoundOnce()
    }

    recordingService.onCaptureLost = { [weak self] in
      guard let self, self.sessionState.isListening else { return }
      self.wasCaptureLost = true
      self.startProcessing { await self.finishListeningAndProcess() }
    }
  }

  func start() {
    guard toggleRecordingMonitor == nil else {
      return
    }

    let toggleMonitor = UnifiedShortcutMonitor(
      store: shortcuts.toggleRecording,
      onKeyDown: { [weak self] in self?.handleShortcutPress() }
    )
    toggleRecordingMonitor = toggleMonitor
    toggleMonitor.activate()

    let holdMonitor = UnifiedShortcutMonitor(
      store: shortcuts.holdToSpeak,
      onKeyDown: { [weak self] in self?.handleHoldToSpeakPress() },
      onKeyUp: { [weak self] in self?.handleHoldToSpeakRelease() }
    )
    holdToSpeakMonitor = holdMonitor
    holdMonitor.activate()

    let retryMonitor = UnifiedShortcutMonitor(
      store: shortcuts.retryLastRecording,
      onKeyDown: { [weak self] in self?.handleRetryLastRecordingPress() }
    )
    retryLastRecordingMonitor = retryMonitor
    retryMonitor.activate()

    escapeHotKeyMonitor = CarbonHotKeyMonitor(
      shortcutProvider: { AppDefaultShortcuts.escape },
      onKeyDown: { [weak self] in self?.handleEscapePress() }
    )

#if DEBUG
    observeDebugDictationCommands()
#endif

    shortcutCaptureObserver = NotificationCenter.default.addObserver(
      forName: .shortcutCaptureStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let isCapturing = notification.userInfo?[ShortcutNotificationUserInfoKey.isCapturing] as? Bool else {
        return
      }

      Task { @MainActor [weak self] in
        self?.handleShortcutCaptureStateChange(isCapturing)
      }
    }
  }

  private func handleShortcutPress() {
    guard !isDebouncedPress() else { return }
    toggleDictation()
  }

  /// What the recording shortcut does: start, stop and process, or cancel processing.
  func toggleDictation() {
    switch sessionState.state {
    case .idle:
      beginListening()
    case .listening:
      startProcessing { await self.finishListeningAndProcess() }
    case .processing:
      cancelProcessingIfAllowed()
    }
  }

  private func isDebouncedPress() -> Bool {
    let now = Date()
    guard now.timeIntervalSince(lastPressDate) >= minimumPressInterval else {
      return true
    }

    lastPressDate = now
    return false
  }

  private func handleEscapePress() {
    isHoldToSpeakActive = false
    cancelDictation()
  }

  /// Throws the current dictation away.
  func cancelDictation() {
    guard sessionState.isListening else { return }
    pendingTranscription?.cancel()
    pendingTranscription = nil
    sessionState.transitionToIdle()
    listeningFlow.cancelListening()
  }

  private func handleShortcutCaptureStateChange(_ isCapturing: Bool) {
    guard isShortcutCaptureActive != isCapturing else {
      return
    }

    isShortcutCaptureActive = isCapturing

    if isCapturing {
      deactivateAllHotKeysForShortcutCapture()
    } else {
      restoreHotKeysAfterShortcutCapture()
    }
  }

  private func deactivateAllHotKeysForShortcutCapture() {
    toggleRecordingMonitor?.deactivate()
    holdToSpeakMonitor?.deactivate()
    retryLastRecordingMonitor?.deactivate()
    escapeHotKeyMonitor?.deactivate()
  }

  private func restoreHotKeysAfterShortcutCapture() {
    toggleRecordingMonitor?.activate()
    holdToSpeakMonitor?.activate()
    retryLastRecordingMonitor?.activate()
    if sessionState.isListening {
      escapeHotKeyMonitor?.activate()
    } else {
      escapeHotKeyMonitor?.deactivate()
    }
  }

  private func handleHoldToSpeakPress() {
    if sessionState.state == .processing {
      cancelProcessingIfAllowed()
      return
    }
    guard sessionState.state == .idle else { return }
    beginListening()
    isHoldToSpeakActive = sessionState.state == .listening
  }

  private func handleHoldToSpeakRelease() {
    guard isHoldToSpeakActive else { return }
    isHoldToSpeakActive = false
    guard sessionState.state == .listening else { return }
    startProcessing { await self.finishListeningAndProcess() }
  }

  private func handleRetryLastRecordingPress() {
    guard !isDebouncedPress(), sessionState.state == .idle else { return }

    guard let recordedAudio = lastRecording.audio else {
      indicator.showStatus(message: "No recording to retry", autoHideAfter: 1.4)
      return
    }

    startProcessing { await self.retryLastRecording(recordedAudio) }
  }

  private func startProcessing(_ work: @escaping () async -> Void) {
    processingStartDate = Date()
    processingTask = Task { await work() }
  }

  /// Cancels the current processing, unless it started less than `minimumProcessingCancelDelay` ago.
  private func cancelProcessingIfAllowed() {
    guard let processingTask,
          Date().timeIntervalSince(processingStartDate) >= minimumProcessingCancelDelay else { return }
    processingTask.cancel()
    self.processingTask = nil
    indicator.showStatus(message: "cancel", autoHideAfter: 1.0)
  }

  private func retryLastRecording(_ recordedAudio: Data) async {
    guard sessionState.transitionToRetryProcessing() else { return }
    defer { sessionState.transitionToIdle() }
    await processingFlowHandler.performRetry(
      recordedAudio: recordedAudio,
      errorMessage: Self.errorMessage(for:)
    )
  }

  private func activateListeningHotKeys() {
    guard !isShortcutCaptureActive else { return }
    escapeHotKeyMonitor?.activate()
  }

  private func deactivateListeningHotKeys() {
    escapeHotKeyMonitor?.deactivate()
  }

  private func finishListeningAndProcess() async {
    isHoldToSpeakActive = false
    guard let transcription = pendingTranscription,
          sessionState.transitionToProcessing() else { return }
    pendingTranscription = nil
    defer { sessionState.transitionToIdle() }
    await processingFlowHandler.performProcessing(
      transcription: transcription,
      wasCaptureLost: wasCaptureLost,
      errorMessage: Self.errorMessage(for:)
    )
  }

  private static func errorMessage(for error: Error) -> String {
    UserFacingErrorMessage.format(error)
  }

  private func beginListening() {
    guard sessionState.state == .idle else { return }
    hasPlayedStartSound = false
    wasCaptureLost = false
    guard let transcription = listeningFlow.startListening(errorMessage: Self.errorMessage(for:)) else { return }
    _ = sessionState.transitionToListening()
    pendingTranscription = transcription
    listeningFlow.showListening()
  }

  /// `NSSound.play()` can block the main thread, so it waits for the indicator to be drawn first.
  private func playStartSoundOnce() {
    guard !hasPlayedStartSound else { return }
    hasPlayedStartSound = true
    DispatchQueue.main.async {
      SoundEffectPlayer.shared.playStart()
    }
  }
}

#if DEBUG
extension Notification.Name {
  /// Posted for `lalfred://debug/start` and `lalfred://debug/cancel`; the object is the command.
  static let debugDictationCommand = Notification.Name("fr.lalfred.dictate.debugDictationCommand")
}

/// Lets `ci/smoke-test.sh` drive real dictations of a Debug build, with the real microphone.
extension AppRuntimeCoordinator {
  fileprivate func observeDebugDictationCommands() {
    debugCommandObserver = NotificationCenter.default.addObserver(
      forName: .debugDictationCommand,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let command = notification.object as? String
      Task { @MainActor [weak self] in
        self?.runDebugDictationCommand(command)
      }
    }
  }

  private func runDebugDictationCommand(_ command: String?) {
    switch command {
    case "start" where sessionState.state == .idle:
      toggleDictation()
    case "cancel":
      cancelDictation()
    default:
      break
    }
  }
}
#endif
