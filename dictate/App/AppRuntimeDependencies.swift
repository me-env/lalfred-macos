import Foundation
import CoreGraphics

protocol AudioRecordingServicing: AnyObject {
    var onAudioLevelUpdate: ((Float) -> Void)? { get set }
    func startRecording() throws
    func stopRecording() async throws -> URL
    func cancelRecording()
}

protocol TranscribingPipeline {
    func runTransformationPipeline(at fileURL: URL) async throws -> String
}

protocol PastingAtCursor {
    func paste(_ text: String) -> Bool
}

@MainActor
protocol IndicatorPresenting: AnyObject {
    func showListening()
    func updateListeningLevel(_ level: CGFloat)
    func showStatus(message: String, autoHideAfter delay: TimeInterval?)
    func hideIndicator()
}

extension AudioRecordingService: AudioRecordingServicing {}
extension ScribeClient: STTProvider {}
extension PasteAtCursorService: PastingAtCursor {}
extension IndicatorPanelController: IndicatorPresenting {}
