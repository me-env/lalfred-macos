import SwiftUI
import Carbon.HIToolbox
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.app", category: "AppRuntimeCoordinator")


@MainActor
final class AppRuntimeCoordinator {
  private let modeCatalog: ModeCatalog
  private let indicator: IndicatorPresenting
  private let pasteService: PastingAtCursor
  private let recordingService: AudioRecordingServicing

  private let holdToSpeakShortcutStore = ShortcutDefaultsStore(key: AppDefaultsKey.shortcutHoldToSpeak)

  private var sessionState = DictationSessionStateMachine()
  
  private var toggleRecordingMonitor: GlobalHotKeyMonitor?
  private var modeSwitcherMonitor: GlobalHotKeyMonitor?
  private var holdToSpeakMonitor: CarbonHotKeyMonitor?
  private var holdToSpeakModifierMonitor: ModifierFlagsMonitor?
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
    modeCatalog: ModeCatalog? = nil,
    indicator: IndicatorPresenting? = nil,
    pasteService: PastingAtCursor? = nil,
    recordingService: AudioRecordingServicing? = nil,
  ) {
    let resolvedModeCatalog = modeCatalog ?? ModeCatalog()
    self.modeCatalog = resolvedModeCatalog
    self.indicator = indicator ?? IndicatorPanelController(modeCatalog: resolvedModeCatalog)
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
  
  private func setDefaultShortcut() {
    holdToSpeakShortcutStore.ensureDefault(AppDefaultShortcuts.holdToSpeak)
  }

  func start() {
    guard toggleRecordingMonitor == nil else {
      return
    }
    
    registerAudioLevelUpdateCallback()
    setDefaultShortcut()

    toggleRecordingMonitor = GlobalHotKeyMonitor(
      storeKey: AppDefaultsKey.shortcutToggleRecording,
      defaultShortcut: AppDefaultShortcuts.toggleRecording
    ) { [weak self] in
      self?.handleShortcutPress()
    }
    rebuildHoldToSpeakMonitor()

    escapeHotKeyMonitor = CarbonHotKeyMonitor(
      shortcutProvider: { AppDefaultShortcuts.escape },
      onKeyDown: { [weak self] in self?.handleEscapePress() }
    )

    modeSwitcherMonitor = GlobalHotKeyMonitor(
      storeKey: AppDefaultsKey.shortcutModeSwitcher,
      defaultShortcut: AppDefaultShortcuts.modeSwitcher
    ) { [weak self] in
      self?.handleModeSwitcherPress()
    }

    indicator.onModeSwitcherSubmit = { [weak self] selection in
      let activeMode = self?.modeCatalog.currentMode.title ?? selection
      logger.info("[ModeSwitcher] Selected: \(activeMode)")
      self?.restoreHotKeysAfterModeSwitcher()
    }

    indicator.onModeSwitcherDismiss = { [weak self] in
      logger.info("[ModeSwitcher] Dismissed")
      self?.restoreHotKeysAfterModeSwitcher()
    }

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

  private func handleModeSwitcherPress() {
    let canShowModeSwitcher = sessionState.canShowModeSwitcher(
      isCommandVisible: indicator.isCommandVisible
    )
    logger.info("[ModeSwitcher] Shortcut detected (state: \(String(describing: self.sessionState.state), privacy: .public), visible: \(self.indicator.isCommandVisible), allowed: \(canShowModeSwitcher))")
    listeningFlow.showModeSwitcherIfPossible(sessionState: sessionState)
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
    deactivateHoldToSpeakMonitor()
    escapeHotKeyMonitor?.deactivate()
  }

  private func restoreHotKeysAfterShortcutCapture() {
    toggleRecordingMonitor?.activate()
    activateHoldToSpeakMonitor()
    modeSwitcherMonitor?.activate()

    if sessionState.isListening && !indicator.isCommandVisible {
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

  private func restoreHotKeysAfterModeSwitcher() {
    listeningFlow.restoreHotKeysAfterModeSwitcher(sessionState: sessionState)
    if !isShortcutCaptureActive {
      modeSwitcherMonitor?.activate()
    }
  }

  private func activateListeningHotKeys() {
    guard !isShortcutCaptureActive else { return }
    escapeHotKeyMonitor?.activate()
    modeSwitcherMonitor?.activate()
  }

  private func deactivateListeningHotKeys() {
    escapeHotKeyMonitor?.deactivate()
  }

  private func finishListeningAndProcess() async {
    isHoldToSpeakActive = false
    guard sessionState.transitionToProcessing() else { return }
    defer { sessionState.transitionToIdle() }
    let modeDefinition = modeCatalog.currentMode
    
    await processingFlowHandler.performProcessing(
      mode: modeDefinition,
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
    rebuildHoldToSpeakMonitor()
  }

  private func rebuildHoldToSpeakMonitor() {
    deactivateHoldToSpeakMonitor()
    holdToSpeakMonitor = nil
    holdToSpeakModifierMonitor = nil

    guard let shortcut = holdToSpeakShortcutStore.load() else { return }

    if shortcut.isModifierOnly {
      holdToSpeakModifierMonitor = ModifierFlagsMonitor(
        targetModifiers: shortcut.modifiers,
        onKeyDown: { [weak self] in
          self?.handleHoldToSpeakPress()
        },
        onKeyUp: { [weak self] in
          self?.handleHoldToSpeakRelease()
        }
      )
    } else {
      holdToSpeakMonitor = CarbonHotKeyMonitor(
        shortcutProvider: { shortcut },
        onKeyDown: { [weak self] in
          self?.handleHoldToSpeakPress()
        },
        onKeyUp: { [weak self] in
          self?.handleHoldToSpeakRelease()
        }
      )
    }

    guard !isShortcutCaptureActive else { return }
    activateHoldToSpeakMonitor()
  }

  private func activateHoldToSpeakMonitor() {
    holdToSpeakMonitor?.activate()
    holdToSpeakModifierMonitor?.activate()
  }

  private func deactivateHoldToSpeakMonitor() {
    holdToSpeakMonitor?.deactivate()
    holdToSpeakModifierMonitor?.deactivate()
  }
}
