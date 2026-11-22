import CoreGraphics
import Foundation
import Testing
@testable import L_Alfred

@MainActor
struct ProcessingFlowSilenceTests {
  private final class FakeRecordingService: AudioRecordingServicing {
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onInputReadinessChange: ((Bool) -> Void)?
    var onInputLive: (() -> Void)?
    var onCaptureLost: (() -> Void)?
    let isInputReady = true
    let recordedAudio: Data

    init(recordedAudio: Data) {
      self.recordedAudio = recordedAudio
    }

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { $0.finish() }
    }

    func stopRecording() async throws -> Data {
      recordedAudio
    }

    func cancelRecording() {}
  }

  private final class FakeIndicator: IndicatorPresenting {
    private(set) var statuses: [String] = []
    func showPreparing() {}
    func showListening() {}
    func updateListeningLevel(_ level: CGFloat) {}
    func showStatus(message: String, autoHideAfter delay: TimeInterval?) { statuses.append(message) }
    func hideIndicator() {}
  }

  private final class FakePaster: PastingAtCursor {
    private(set) var pasted: [String] = []
    func paste(_ text: String) -> Bool {
      pasted.append(text)
      return true
    }
  }

  private func process(_ recordedAudio: Data, wasCaptureLost: Bool) async -> (statuses: [String], pasted: [String]) {
    let indicator = FakeIndicator()
    let paster = FakePaster()
    let handler = ProcessingFlowHandler(
      recordingService: FakeRecordingService(recordedAudio: recordedAudio),
      lastRecording: LastRecordingStore(),
      pasteService: paster,
      indicator: indicator,
      deactivateListeningHotKeys: {}
    )
    await handler.performProcessing(
      transcription: Task { "Hello there" },
      wasCaptureLost: wasCaptureLost,
      errorMessage: { _ in "error" }
    )
    return (indicator.statuses, paster.pasted)
  }

  private var speech: Data {
    var audio = Data(count: 3_200)
    audio[10] = 42
    return audio
  }

  @Test func silentRecordingIsNotTranscribed() async {
    let result = await process(Data(count: 3_200), wasCaptureLost: false)
    #expect(result.pasted.isEmpty)
    #expect(result.statuses.last == "No sound from the microphone")
  }

  @Test func lostCaptureWithoutAudioSaysTheMicWasLost() async {
    let result = await process(Data(), wasCaptureLost: true)
    #expect(result.pasted.isEmpty)
    #expect(result.statuses.last == "Microphone lost")
  }

  @Test func lostCapturePastesWhatWasRecorded() async {
    let result = await process(speech, wasCaptureLost: true)
    #expect(result.pasted == ["Hello there"])
    #expect(result.statuses.last == "Microphone lost, pasted what was recorded")
  }

  @Test func normalRecordingIsPasted() async {
    let result = await process(speech, wasCaptureLost: false)
    #expect(result.pasted == ["Hello there"])
    #expect(result.statuses.last == "Pasted")
  }
}
