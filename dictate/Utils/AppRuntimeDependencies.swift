import Foundation
import CoreGraphics

protocol AudioRecordingServicing: AnyObject {
    var onAudioLevelUpdate: ((Float) -> Void)? { get set }
    func startRecording() throws
    func stopRecording() async throws -> URL
    func cancelRecording()
}

protocol Transcribing {
    func transcribeAudio(at fileURL: URL) async throws -> String
}

protocol PastingAtCursor {
    func paste(_ text: String) -> Bool
}

@MainActor
protocol IndicatorPresenting: AnyObject {
    var onModeSwitcherSubmit: ((String) -> Void)? { get set }
    var onModeSwitcherDismiss: (() -> Void)? { get set }
    var isModeSwitcherVisible: Bool { get }

    func showListening()
    func updateListeningLevel(_ level: CGFloat)
    func showStatus(message: String, autoHideAfter delay: TimeInterval?)
    func showModeSwitcher()
    func dismissModeSwitcher()
}

extension AudioRecordingService: AudioRecordingServicing {}
extension ScribeClient: Transcribing {}
extension PasteAtCursorService: PastingAtCursor {}
extension IndicatorPanelController: IndicatorPresenting {}
