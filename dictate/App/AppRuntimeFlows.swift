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
      SoundEffectPlayer.shared.playStart()
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 2.2)
    }
  }
  
  func cancelListeningIfNeeded(sessionState: inout DictationSessionStateMachine) {
    guard sessionState.isListening else { return }
    recordingService.cancelRecording()
    sessionState.transitionToIdle()
    deactivateListeningHotKeys()
    indicator.hideIndicator()
  }
  
}

@MainActor
struct ProcessingFlowHandler {
  let recordingService: AudioRecordingServicing
  let pasteService: PastingAtCursor
  let indicator: IndicatorPresenting
  let deactivateListeningHotKeys: () -> Void
  
  func performProcessing(
    errorMessage: (Error) -> String
  ) async {
    deactivateListeningHotKeys()

    SoundEffectPlayer.shared.playStop()

    indicator.showStatus(message: "Processing", autoHideAfter: nil)

    do {
      try await Task.sleep(for: .milliseconds(250))
      let audioFileURL = try await recordingService.stopRecording()
      defer { try? FileManager.default.removeItem(at: audioFileURL) }
      
      let transcript = try await runTransformationPipeline(at: audioFileURL)
      onTranscriptionPipelineResult(transcript)
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 1.8)
    }
  }
  
  private func onTranscriptionPipelineResult(_ transcript: String) {
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
