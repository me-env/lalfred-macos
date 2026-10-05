import Foundation


@MainActor
struct ListeningFlowHandler {
  let recordingService: AudioRecordingServicing
  let indicator: IndicatorPresenting
  let activateListeningHotKeys: () -> Void
  let deactivateListeningHotKeys: () -> Void
  
  /// Starts recording and the transcription request, which receives audio while the user speaks.
  func beginListening(
    sessionState: inout DictationSessionStateMachine,
    errorMessage: (Error) -> String
  ) -> Task<String, Error>? {
    guard sessionState.state == .idle else { return nil }

    do {
      let audio = try recordingService.startRecording()
      let transcription = Task { try await runTransformationPipeline(audio: audio) }
      _ = sessionState.transitionToListening()
      activateListeningHotKeys()
      if recordingService.isInputReady {
        indicator.showListening()
      } else {
        indicator.showPreparing()
      }
      return transcription
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 2.2)
      return nil
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
  let lastRecording: LastRecordingStore
  let pasteService: PastingAtCursor
  let indicator: IndicatorPresenting
  let deactivateListeningHotKeys: () -> Void
  
  func performProcessing(
    transcription: Task<String, Error>,
    errorMessage: (Error) -> String
  ) async {
    deactivateListeningHotKeys()

    SoundEffectPlayer.shared.playStop()

    indicator.showStatus(message: "Processing", autoHideAfter: nil)

    do {
      let recordedAudio = try await recordingService.stopRecording()
      lastRecording.save(recordedAudio)

      let transcript: String
      do {
        // Awaiting a task's value doesn't forward cancellation to it, so cancel the request explicitly.
        transcript = try await withTaskCancellationHandler {
          try await transcription.value
        } onCancel: {
          transcription.cancel()
        }
      } catch where !Task.isCancelled && TranscriptionRetryPolicy.isTransient(error) {
        try await Task.sleep(for: TranscriptionRetryPolicy.autoRetryDelay)
        transcript = try await runTransformationPipeline(recordedAudio: recordedAudio)
      }
      try Task.checkCancellation()
      onTranscriptionPipelineResult(transcript)
    } catch {
      transcription.cancel()
      // A cancelled processing already shows its own status.
      guard !Task.isCancelled else { return }
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 2.5)
    }
  }

  /// Transcribes the kept recording again and pastes the result at the current cursor.
  func performRetry(
    recordedAudio: Data,
    errorMessage: (Error) -> String
  ) async {
    indicator.showStatus(message: "Processing", autoHideAfter: nil)

    do {
      let transcript = try await runTransformationPipeline(recordedAudio: recordedAudio)
      try Task.checkCancellation()
      onTranscriptionPipelineResult(transcript)
    } catch {
      guard !Task.isCancelled else { return }
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
