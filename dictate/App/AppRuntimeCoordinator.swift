import SwiftUI
import Carbon.HIToolbox
@MainActor
final class AppRuntimeCoordinator {
  private let indicator: IndicatorPresenting
  private let pasteService: PastingAtCursor
  private let recordingService: AudioRecordingServicing

  private let toggleRecordingShortcutStore = ShortcutDefaultsStore(key: AppDefaultsKey.shortcutToggleRecording)
  private let holdToSpeakShortcutStore = ShortcutDefaultsStore(key: AppDefaultsKey.shortcutHoldToSpeak)

  private var sessionState = DictationSessionStateMachine()
  
  private var toggleRecordingMonitor: UnifiedShortcutMonitor?
  private var holdToSpeakMonitor: UnifiedShortcutMonitor?
  private var escapeHotKeyMonitor: CarbonHotKeyMonitor?
  
  private var shortcutCaptureObserver: NSObjectProtocol?
  private var shortcutDidChangeObserver: NSObjectProtocol?
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
    indicator: IndicatorPresenting? = nil,
    pasteService: PastingAtCursor? = nil,
    recordingService: AudioRecordingServicing? = nil,
  ) {
    self.indicator = indicator ?? IndicatorPanelController()
    self.pasteService = pasteService ?? PasteAtCursorService()
    self.recordingService = recordingService ?? AudioRecordingService()
  }

  deinit {
    if let shortcutCaptureObserver {
      NotificationCenter.default.removeObserver(shortcutCaptureObserver)
    }
    if let shortcutDidChangeObserver {
      NotificationCenter.default.removeObserver(shortcutDidChangeObserver)
    }
  }
  
  private func registerAudioLevelUpdateCallback() {
    recordingService.onAudioLevelUpdate = { [weak self] level in
      guard let self, self.sessionState.isListening else { return }
      self.indicator.updateListeningLevel(CGFloat(level))
    }
  }
  
  private func setDefaultShortcuts() {
    toggleRecordingShortcutStore.ensureDefault(AppDefaultShortcuts.toggleRecording)
    holdToSpeakShortcutStore.ensureDefault(AppDefaultShortcuts.holdToSpeak)
  }

  func start() {
    guard toggleRecordingMonitor == nil else {
      return
    }
    
    registerAudioLevelUpdateCallback()
    setDefaultShortcuts()

    rebuildToggleRecordingMonitor()
    rebuildHoldToSpeakMonitor()

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

    shortcutDidChangeObserver = NotificationCenter.default.addObserver(
      forName: .shortcutDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleShortcutDidChange()
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
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
      return description
    }

    return "Something went wrong"
  }

  private func beginListening() {
    listeningFlow.beginListening(
      sessionState: &sessionState,
      errorMessage: Self.errorMessage(for:)
    )
  }

  private func handleShortcutDidChange() {
    rebuildToggleRecordingMonitor()
    rebuildHoldToSpeakMonitor()
  }

  private func rebuildToggleRecordingMonitor() {
    toggleRecordingMonitor?.deactivate()
    toggleRecordingMonitor = nil

    toggleRecordingMonitor = UnifiedShortcutMonitor(
      shortcutProvider: { [toggleRecordingShortcutStore] in
        toggleRecordingShortcutStore.load()
      },
      onKeyDown: { [weak self] in
        self?.handleShortcutPress()
      }
    )

    guard !isShortcutCaptureActive else { return }
    toggleRecordingMonitor?.activate()
  }

  private func rebuildHoldToSpeakMonitor() {
    holdToSpeakMonitor?.deactivate()
    holdToSpeakMonitor = nil

    guard holdToSpeakShortcutStore.load() != nil else { return }

    holdToSpeakMonitor = UnifiedShortcutMonitor(
      shortcutProvider: { [holdToSpeakShortcutStore] in
        holdToSpeakShortcutStore.load()
      },
      onKeyDown: { [weak self] in
        self?.handleHoldToSpeakPress()
      },
      onKeyUp: { [weak self] in
        self?.handleHoldToSpeakRelease()
      }
    )

    guard !isShortcutCaptureActive else { return }
    holdToSpeakMonitor?.activate()
  }
}
