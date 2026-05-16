import SwiftUI
import Carbon.HIToolbox


@MainActor
final class AppRuntimeCoordinator {
  private let shortcuts: Shortcuts
  private let indicator: IndicatorPresenting
  private let pasteService: PastingAtCursor
  private let recordingService: AudioRecordingServicing

  private var sessionState = DictationSessionStateMachine()

  private var toggleRecordingMonitor: UnifiedShortcutMonitor?
  private var holdToSpeakMonitor: UnifiedShortcutMonitor?
  private var escapeHotKeyMonitor: CarbonHotKeyMonitor?

  private var shortcutCaptureObserver: NSObjectProtocol?
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
  }

  deinit {
    if let shortcutCaptureObserver {
      NotificationCenter.default.removeObserver(shortcutCaptureObserver)
    }
  }

  private func registerAudioLevelUpdateCallback() {
    recordingService.onAudioLevelUpdate = { [weak self] level in
      guard let self, self.sessionState.isListening else { return }
      self.indicator.updateListeningLevel(CGFloat(level))
    }
  }

  func start() {
    guard toggleRecordingMonitor == nil else {
      return
    }

    registerAudioLevelUpdateCallback()

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

    escapeHotKeyMonitor = CarbonHotKeyMonitor(
      shortcutProvider: { AppDefaultShortcuts.escape },
      onKeyDown: { [weak self] in self?.handleEscapePress() }
    )

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

    switch sessionState.state {
    case .idle:
      beginListening()
    case .listening:
      Task {
        await finishListeningAndProcess()
      }
    case .processing:
      return
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
    listeningFlow.cancelListeningIfNeeded(sessionState: &sessionState)
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
    escapeHotKeyMonitor?.deactivate()
  }

  private func restoreHotKeysAfterShortcutCapture() {
    toggleRecordingMonitor?.activate()
    holdToSpeakMonitor?.activate()
    if sessionState.isListening {
      escapeHotKeyMonitor?.activate()
    } else {
      escapeHotKeyMonitor?.deactivate()
    }
  }

  private func handleHoldToSpeakPress() {
    guard sessionState.state == .idle else { return }
    beginListening()
    isHoldToSpeakActive = sessionState.state == .listening
  }

  private func handleHoldToSpeakRelease() {
    guard isHoldToSpeakActive else { return }
    isHoldToSpeakActive = false
    guard sessionState.state == .listening else { return }
    Task {
      await finishListeningAndProcess()
    }
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
    guard sessionState.transitionToProcessing() else { return }
    defer { sessionState.transitionToIdle() }
    await processingFlowHandler.performProcessing(
      errorMessage: Self.errorMessage(for:)
    )
  }

  private static func errorMessage(for error: Error) -> String {
    UserFacingErrorMessage.format(error)
  }

  private func beginListening() {
    listeningFlow.beginListening(
      sessionState: &sessionState,
      errorMessage: Self.errorMessage(for:)
    )
  }
}
