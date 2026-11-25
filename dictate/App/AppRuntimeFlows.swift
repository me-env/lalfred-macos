import Foundation


@MainActor
struct ListeningFlowHandler {
  let recordingService: AudioRecordingServicing
  let indicator: IndicatorPresenting
  let activateListeningHotKeys: () -> Void
  let deactivateListeningHotKeys: () -> Void
  
  /// Starts recording and the transcription request, which receives audio while the user speaks.
  /// Takes no session state: the recording service may call back into its owner while starting.
  func startListening(errorMessage: (Error) -> String) -> Task<String, Error>? {
    do {
      let audio = try recordingService.startRecording()
      return Task { try await runTransformationPipeline(audio: audio) }
    } catch {
      indicator.showStatus(message: errorMessage(error), autoHideAfter: 2.2)
      return nil
    }
  }

  func showListening() {
    activateListeningHotKeys()
    if recordingService.isInputReady {
      indicator.showListening()
    } else {
      indicator.showPreparing()
    }
  }

  func cancelListening() {
    recordingService.cancelRecording()
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
  
  /// `wasCaptureLost`: the microphone failed mid-recording and the recording ended on its own.
  func performProcessing(
    transcription: Task<String, Error>,
    wasCaptureLost: Bool,
    errorMessage: (Error) -> String
  ) async {
    deactivateListeningHotKeys()

    SoundEffectPlayer.shared.playStop()

    indicator.showStatus(message: "Processing", autoHideAfter: nil)

    do {
      let recordedAudio = try await recordingService.stopRecording()
      guard !RecordedAudio.isDigitallySilent(recordedAudio) else {
        transcription.cancel()
        indicator.showStatus(message: wasCaptureLost ? "Microphone lost" : "No sound from the microphone", autoHideAfter: 2.2)
        return
      }
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
      onTranscriptionPipelineResult(transcript, wasCaptureLost: wasCaptureLost)
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
  
  private func onTranscriptionPipelineResult(_ transcript: String, wasCaptureLost: Bool = false) {
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
    
    guard !wasCaptureLost else {
      indicator.showStatus(message: "Microphone lost, pasted what was recorded", autoHideAfter: 2.5)
      return
    }
    indicator.showStatus(message: "Pasted", autoHideAfter: 1.0)
  }
}
