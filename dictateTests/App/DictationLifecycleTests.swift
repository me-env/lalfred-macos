import Foundation
import Testing
@testable import L_Alfred

/// Drives the coordinator through whole dictations. Each scenario runs in an exit test: an
/// exclusivity violation (the v1.16.16 crash) aborts the process and fails only that test.
@MainActor
struct DictationLifecycleTests {
  /// Calls back synchronously from inside every call, the worst case for re-entrancy: the real
  /// service defers its callbacks, but the coordinator must not depend on it.
  final class ReentrantRecordingService: AudioRecordingServicing {
    var onAudioLevelsUpdate: ((ListeningLevels) -> Void)?
    var onInputReadinessChange: ((Bool) -> Void)?
    var onInputLive: (() -> Void)?
    var onCaptureLost: (() -> Void)?
    private(set) var isInputReady = false
    private(set) var stopCount = 0
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func startRecording(needsHeadsetSwitch: Bool) throws -> AsyncThrowingStream<Data, Error> {
      let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
      self.continuation = continuation
      setInputReady(!needsHeadsetSwitch)
      onAudioLevelsUpdate?(ListeningLevels(clamping: SIMD8(repeating: 0.5)))
      return stream
    }

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
      try startRecording(needsHeadsetSwitch: false)
    }

    func markInputLive() {
      setInputReady(true)
      onInputLive?()
    }

    func loseCapture() {
      continuation?.finish()
      onCaptureLost?()
    }

    func stopRecording() async throws -> Data {
      stopCount += 1
      continuation?.finish()
      setInputReady(false)
      return Data(count: 3_200) // silent: processing ends without calling a provider
    }

    func cancelRecording() {
      continuation?.finish(throwing: CancellationError())
      setInputReady(false)
    }

    private func setInputReady(_ isReady: Bool) {
      guard isInputReady != isReady else { return }
      isInputReady = isReady
      onInputReadinessChange?(isReady)
    }
  }

  /// A service whose `startRecording()` answers `needsHeadsetSwitch` from a script.
  final class ScriptedRecordingService: AudioRecordingServicing {
    let service = ReentrantRecordingService()
    var needsHeadsetSwitchPerStart: [Bool]

    init(needsHeadsetSwitchPerStart: [Bool]) {
      self.needsHeadsetSwitchPerStart = needsHeadsetSwitchPerStart
    }

    var onAudioLevelsUpdate: ((ListeningLevels) -> Void)? { get { service.onAudioLevelsUpdate } set { service.onAudioLevelsUpdate = newValue } }
    var onInputReadinessChange: ((Bool) -> Void)? { get { service.onInputReadinessChange } set { service.onInputReadinessChange = newValue } }
    var onInputLive: (() -> Void)? { get { service.onInputLive } set { service.onInputLive = newValue } }
    var onCaptureLost: (() -> Void)? { get { service.onCaptureLost } set { service.onCaptureLost = newValue } }
    var isInputReady: Bool { service.isInputReady }

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
      try service.startRecording(needsHeadsetSwitch: needsHeadsetSwitchPerStart.removeFirst())
    }

    func stopRecording() async throws -> Data { try await service.stopRecording() }
    func cancelRecording() { service.cancelRecording() }
  }

  final class FakeIndicator: IndicatorPresenting {
    func showPreparing() {}
    func showListening() {}
    func updateListeningLevels(_ levels: ListeningLevels) {}
    func showStatus(message: String, autoHideAfter delay: TimeInterval?) {}
    func hideIndicator() {}
  }

  final class FakePaster: PastingAtCursor {
    func paste(_ text: String) -> Bool { true }
  }

  static func makeCoordinator(_ service: AudioRecordingServicing) -> AppRuntimeCoordinator {
    AppRuntimeCoordinator(shortcuts: Shortcuts(), indicator: FakeIndicator(), pasteService: FakePaster(), recordingService: service)
  }

  static func waitUntilIdle(_ coordinator: AppRuntimeCoordinator) async {
    while coordinator.sessionState.state != .idle { await Task.yield() }
  }

  /// Start → live → stop → processed, once per entry.
  static func runDictations(needsHeadsetSwitchPerStart: [Bool]) async {
    let service = ScriptedRecordingService(needsHeadsetSwitchPerStart: needsHeadsetSwitchPerStart)
    let coordinator = makeCoordinator(service)
    for _ in needsHeadsetSwitchPerStart.indices {
      coordinator.toggleDictation()
      precondition(coordinator.sessionState.isListening, "dictation did not start")
      service.service.markInputLive()
      coordinator.toggleDictation()
      await waitUntilIdle(coordinator)
    }
    precondition(service.service.stopCount == needsHeadsetSwitchPerStart.count, "not every dictation was processed")
  }

  @Test func oneDictationOnBuiltInMic() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.runDictations(needsHeadsetSwitchPerStart: [false])
    }
  }

  @Test func twoDictationsOnBuiltInMic() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.runDictations(needsHeadsetSwitchPerStart: [false, false])
    }
  }

  /// A headset back in music mode between dictations switches profile at every start.
  @Test func twoDictationsOnBluetoothHeadset() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.runDictations(needsHeadsetSwitchPerStart: [true, true])
    }
  }

  @Test func fiveDictationsAlternatingMicrophones() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.runDictations(needsHeadsetSwitchPerStart: [false, true, true, false, true])
    }
  }

  @Test func cancelThenDictateAgain() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.cancelThenDictate()
    }
  }

  @Test func lostCaptureEndsTheDictationThenDictateAgain() async {
    await #expect(processExitsWith: .success) {
      await DictationLifecycleTests.loseCaptureThenDictate()
    }
  }

  static func cancelThenDictate() async {
    let service = ReentrantRecordingService()
    let coordinator = makeCoordinator(service)
    coordinator.toggleDictation()
    coordinator.cancelDictation()
    precondition(coordinator.sessionState.state == .idle, "cancel did not return to idle")
    coordinator.toggleDictation()
    coordinator.toggleDictation()
    await waitUntilIdle(coordinator)
    precondition(service.stopCount == 1, "the dictation after a cancel was not processed")
  }

  static func loseCaptureThenDictate() async {
    let service = ReentrantRecordingService()
    let coordinator = makeCoordinator(service)
    coordinator.toggleDictation()
    service.markInputLive()
    service.loseCapture()
    await waitUntilIdle(coordinator)
    precondition(service.stopCount == 1, "a lost capture did not end the dictation")
    coordinator.toggleDictation()
    coordinator.toggleDictation()
    await waitUntilIdle(coordinator)
    precondition(service.stopCount == 2, "the dictation after a lost capture was not processed")
  }
}
