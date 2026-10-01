import Foundation
import CoreGraphics

protocol AudioRecordingServicing: AnyObject {
    var onAudioLevelUpdate: ((Float) -> Void)? { get set }
    /// Called when the microphone becomes ready, or stops being ready while the capture restarts.
    var onInputReadinessChange: ((Bool) -> Void)? { get set }
    /// False while the input device is still switching on, e.g. a Bluetooth headset changing profile.
    var isInputReady: Bool { get }
    func startRecording() throws -> AsyncThrowingStream<Data, Error>
    func stopRecording() async throws -> Data
    func cancelRecording()
}

protocol PastingAtCursor {
    func paste(_ text: String) -> Bool
}

@MainActor
protocol IndicatorPresenting: AnyObject {
    func showPreparing()
    func showListening()
    func updateListeningLevel(_ level: CGFloat)
    func showStatus(message: String, autoHideAfter delay: TimeInterval?)
    func hideIndicator()
}

extension AudioRecordingService: AudioRecordingServicing {}
extension ScribeClient: STTProvider {}
extension ScribeRealtimeClient: STTProvider {}
extension VoxtralClient: STTProvider {}
extension VoxtralRealtimeClient: STTProvider {}
extension PasteAtCursorService: PastingAtCursor {}
extension IndicatorPanelController: IndicatorPresenting {}
