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
  private enum RuntimeState {
    case idle
    case listening
    case processing
  }
  
  private let indicator = IndicatorPanelController()
  private let pasteService = PasteAtCursorService()
  private let recordingService = AudioRecordingService()
  private let scribeClient = ScribeClient()
  
  private var hotKeyMonitor: GlobalHotKeyMonitor?
  private var escapeHotKeyMonitor: EscapeHotKeyMonitor?
  private var state: RuntimeState = .idle
  private var lastPressDate: Date = .distantPast
  private let minimumPressInterval: TimeInterval = 0.30
  
  func start() {
    guard hotKeyMonitor == nil else {
      return
    }

    recordingService.onAudioLevelUpdate = { [weak self] level in
      self?.indicator.updateListeningLevel(CGFloat(level))
    }
    
    hotKeyMonitor = GlobalHotKeyMonitor { [weak self] in
      self?.handleShortcutPress()
    }
    escapeHotKeyMonitor = EscapeHotKeyMonitor { [weak self] in
      self?.handleEscapePress()
    }
  }
  
  private func handleShortcutPress() {
    guard !isDebouncedPress() else {
      return
    }
    
    switch state {
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
    guard state == .listening else {
      return
    }

    recordingService.cancelRecording()
    state = .idle
    escapeHotKeyMonitor?.deactivate()
    indicator.showStatus(message: "Cancel", autoHideAfter: 1.2)
  }
  
  private func beginListening() {
    do {
      try recordingService.startRecording()
      state = .listening
      escapeHotKeyMonitor?.activate()
      indicator.showListening()
    } catch {
      let message = errorMessage(for: error)
      indicator.showStatus(message: message, autoHideAfter: 1.8)
    }
  }
  
  private func finishListeningAndProcess() async {
    guard state == .listening else {
      return
    }
    
    state = .processing
    escapeHotKeyMonitor?.deactivate()
    indicator.showStatus(message: "Processing")

    do {
      try await Task.sleep(for: .milliseconds(500))
      let audioFileURL = try await recordingService.stopRecording()
      defer { removeTemporaryFileIfNeeded(at: audioFileURL) }
      
      let transcript = try await scribeClient.transcribeAudio(at: audioFileURL)
      handleTranscriptSuccess(transcript)
    } catch {
      handleProcessingFailure(error)
    }
    
    state = .idle
  }
  
  private func handleTranscriptSuccess(_ transcript: String) {
    let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTranscript.isEmpty else {
      indicator.showStatus(message: "No speech recognized", autoHideAfter: 1.4)
      return
    }
    
    let didPaste = pasteService.paste(cleanedTranscript)
    guard didPaste else {
      indicator.showStatus(message: "Paste failed (check Accessibility)", autoHideAfter: 1.8)
      return
    }
    
    indicator.showStatus(message: "Pasted", autoHideAfter: 1.0)
  }
  
  private func handleProcessingFailure(_ error: Error) {
    let message = errorMessage(for: error)
    indicator.showStatus(message: message, autoHideAfter: 1.8)
  }
  
  private func removeTemporaryFileIfNeeded(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
  
  private func errorMessage(for error: Error) -> String {
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
      return description
    }
    
    return "Something went wrong"
  }
}

private final class EscapeHotKeyMonitor {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private let hotKeyID = EventHotKeyID(signature: OSType(0x44494354), id: 2) // 'DICT'

  private let onTrigger: @MainActor () -> Void

  init(onTrigger: @escaping @MainActor () -> Void) {
    self.onTrigger = onTrigger
    installHandlerIfNeeded()
  }

  deinit {
    deactivate()
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }

  func activate() {
    guard hotKeyRef == nil else {
      return
    }

    let status = RegisterEventHotKey(
      UInt32(kVK_Escape),
      0,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status != noErr {
      hotKeyRef = nil
      print("Failed to register Escape hot key: \(status)")
    }
  }

  func deactivate() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
  }

  private func installHandlerIfNeeded() {
    guard eventHandlerRef == nil else { return }

    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event,
              let userData else {
          return noErr
        }

        let monitor = Unmanaged<EscapeHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()

        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &receivedID
        )

        guard status == noErr,
              receivedID.id == monitor.hotKeyID.id,
              receivedID.signature == monitor.hotKeyID.signature else {
          return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
          monitor.onTrigger()
        }
        return noErr
      },
      1,
      &eventSpec,
      selfPointer,
      &eventHandlerRef
    )
  }
}
