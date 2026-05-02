//
//  AppRuntimeCoordinator.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppRuntimeCoordinator {
  private let modeStateStore: ModeStateStore
  private let indicator: IndicatorPresenting
  private let pasteService: PastingAtCursor
  private let recordingService: AudioRecordingServicing
  private let transcriptionService: TranscribingPipeline

  private let modeSwitcherShortcutStore = ShortcutDefaultsStore(key: AppDefaultsKey.shortcutModeSwitcher)
  private let modeSwitcherFallbackShortcut = Shortcut(
    keyCode: KeyCode.from(character: "/") ?? UInt16(kVK_ANSI_Slash),
    modifiers: [.command]
  )
  private let holdToSpeakShortcutStore = ShortcutDefaultsStore(key: AppDefaultsKey.shortcutHoldToSpeak)
  private let holdToSpeakFallbackShortcut = Shortcut(
    keyCode: Shortcut.modifierOnlyKeyCode,
    modifiers: [.option, .control]
  )

  private var sessionState = DictationSessionStateMachine()
  private var toggleRecordingMonitor: GlobalHotKeyMonitor?
  private var holdToSpeakMonitor: CarbonHotKeyMonitor?
  private var holdToSpeakModifierMonitor: ModifierFlagsMonitor?
  private var escapeHotKeyMonitor: CarbonHotKeyMonitor?
  private var modeSwitcherMonitor: CarbonHotKeyMonitor?
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
    transcriptionPipeline: transcriptionService,
    pasteService: pasteService,
    indicator: indicator,
    deactivateListeningHotKeys: { [weak self] in
      self?.deactivateListeningHotKeys()
    }
  )

  init(
    modeStateStore: ModeStateStore? = nil,
    indicator: IndicatorPresenting? = nil,
    pasteService: PastingAtCursor? = nil,
    recordingService: AudioRecordingServicing? = nil,
    transcriptionService: TranscribingPipeline? = nil
  ) {
    let resolvedModeStateStore = modeStateStore ?? ModeStateStore()
    self.modeStateStore = resolvedModeStateStore
    self.indicator = indicator ?? IndicatorPanelController(modeStateStore: resolvedModeStateStore)
    self.pasteService = pasteService ?? PasteAtCursorService()
    self.recordingService = recordingService ?? AudioRecordingService()
    self.transcriptionService = transcriptionService ?? TranscriptionPipeline()
  }

  deinit {
    if let shortcutCaptureObserver {
      NotificationCenter.default.removeObserver(shortcutCaptureObserver)
    }
    if let shortcutDidChangeObserver {
      NotificationCenter.default.removeObserver(shortcutDidChangeObserver)
    }
  }

  func start() {
    guard toggleRecordingMonitor == nil else {
      return
    }

    recordingService.onAudioLevelUpdate = { [weak self] level in
      guard let self, self.sessionState.isListening else { return }
      self.indicator.updateListeningLevel(CGFloat(level))
    }

    holdToSpeakShortcutStore.ensureDefault(holdToSpeakFallbackShortcut)
    modeSwitcherShortcutStore.ensureDefault(modeSwitcherFallbackShortcut)

    toggleRecordingMonitor = GlobalHotKeyMonitor { [weak self] in
      self?.handleShortcutPress()
    }
    rebuildHoldToSpeakMonitor()

    escapeHotKeyMonitor = CarbonHotKeyMonitor(
      id: 2,
      shortcutProvider: {
        Shortcut(keyCode: UInt16(kVK_Escape), modifiers: [])
      },
      onKeyDown: { [weak self] in
        self?.handleEscapePress()
      }
    )

    modeSwitcherMonitor = CarbonHotKeyMonitor(
      id: 3,
      shortcutProvider: { [modeSwitcherShortcutStore] in
        modeSwitcherShortcutStore.load()
      },
      reloadOnShortcutChange: true,
      onKeyDown: { [weak self] in
        self?.handleModeSwitcherPress()
      }
    )

    indicator.onModeSwitcherSubmit = { [weak self] selection in
      let activeMode = self?.modeStateStore.currentMode.title ?? selection
      print("[ModeSwitcher] Selected: \(activeMode)")
      self?.restoreHotKeysAfterModeSwitcher()
    }

    indicator.onModeSwitcherDismiss = { [weak self] in
      print("[ModeSwitcher] Dismissed")
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
    guard !isDebouncedPress() else {
      return
    }

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
    modeSwitcherMonitor?.deactivate()
  }

  private func restoreHotKeysAfterShortcutCapture() {
    toggleRecordingMonitor?.activate()
    activateHoldToSpeakMonitor()

    if sessionState.isListening && !indicator.isModeSwitcherVisible {
      escapeHotKeyMonitor?.activate()
      modeSwitcherMonitor?.activate()
    } else {
      escapeHotKeyMonitor?.deactivate()
      modeSwitcherMonitor?.deactivate()
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
  }

  private func activateListeningHotKeys() {
    guard !isShortcutCaptureActive else { return }
    escapeHotKeyMonitor?.activate()
    modeSwitcherMonitor?.activate()
  }

  private func deactivateListeningHotKeys() {
    escapeHotKeyMonitor?.deactivate()
    modeSwitcherMonitor?.deactivate()
  }

  private func finishListeningAndProcess() async {
    isHoldToSpeakActive = false
    guard sessionState.transitionToProcessing() else { return }
    defer { sessionState.transitionToIdle() }
    let modeContext = makeModeTranscriptionContext()
    
    await processingFlowHandler.performProcessing(
      context: modeContext,
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

  private func makeModeTranscriptionContext() -> ModeTranscriptionContext {
    let currentMode = modeStateStore.currentMode
    let modeDefinition = ModeCatalog.definition(for: currentMode.id)
    
    return ModeTranscriptionContext(
      modeID: currentMode.id,
      modeTitle: currentMode.title,
      additionalVocabulary: modeDefinition?.additionalVocabulary ?? [],
      llmInstruction: modeDefinition?.llmInstruction
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
        id: 4,
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
