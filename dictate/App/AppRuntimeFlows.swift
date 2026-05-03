import Foundation


@MainActor
struct ListeningFlowHandler {
  let recordingService: AudioRecordingServicing
  let indicator: IndicatorPresenting
  let activateListeningHotKeys: () -> Void
  let deactivateListeningHotKeys: () -> Void
  
  func beginListening(
    sessionState: inout DictationSessionStateMachine,
    errorMessage: (Error) -> String
  ) {
    guard sessionState.state == .idle else { return }

    do {
      try recordingService.startRecording()
      _ = sessionState.transitionToListening()
      activateListeningHotKeys()
      indicator.showListening()
      // Audible cue that we're now listening — fires only after the recorder
      // is actually live, so the start sound never plays on a failed start.
      SoundEffectPlayer.shared.playStart()
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 1.8)
    }
  }
  
  func cancelListeningIfNeeded(sessionState: inout DictationSessionStateMachine) {
    guard sessionState.isListening else { return }
    recordingService.cancelRecording()
    sessionState.transitionToIdle()
    deactivateListeningHotKeys()
    indicator.hideIndicator()
  }
  
  func showModeSwitcherIfPossible(sessionState: DictationSessionStateMachine) {
    guard sessionState.canShowModeSwitcher(isModeSwitcherVisible: indicator.isModeSwitcherVisible) else {
      return
    }
    deactivateListeningHotKeys()
    indicator.showModeSwitcher()
  }
  
  func restoreHotKeysAfterModeSwitcher(sessionState: DictationSessionStateMachine) {
    guard sessionState.isListening else { return }
    activateListeningHotKeys()
  }
}

@MainActor
struct ProcessingFlowHandler {
  let recordingService: AudioRecordingServicing
  let pasteService: PastingAtCursor
  let indicator: IndicatorPresenting
  let deactivateListeningHotKeys: () -> Void
  
  func performProcessing(
    mode: ModeDefinition,
    errorMessage: (Error) -> String
  ) async {
    deactivateListeningHotKeys()

    // Stop cue at the user-perceived moment of release, before the
    // 500 ms tail and the network round-trip.
    SoundEffectPlayer.shared.playStop()

    if indicator.isModeSwitcherVisible {
      indicator.dismissModeSwitcher()
    }

    indicator.showStatus(message: "Processing", autoHideAfter: nil)

    do {
      try await Task.sleep(for: .milliseconds(500))
      let audioFileURL = try await recordingService.stopRecording()
      defer { try? FileManager.default.removeItem(at: audioFileURL) }
      
      let transcript = try await runTransformationPipeline(at: audioFileURL, mode: mode)
      handleTranscriptSuccess(transcript)
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 1.8)
    }
  }
  
  private func handleTranscriptSuccess(_ transcript: String) {
    let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTranscript.isEmpty else {
      indicator.showStatus(message: "NoSpeech", autoHideAfter: 1.4)
      return
    }
    
    let didPaste = pasteService.paste(cleanedTranscript)
    guard didPaste else {
      indicator.showStatus(message: "Paste failed (check Accessibility)", autoHideAfter: 1.8)
      return
    }
    
    indicator.showStatus(message: "Pasted", autoHideAfter: 1.0)
  }
}
