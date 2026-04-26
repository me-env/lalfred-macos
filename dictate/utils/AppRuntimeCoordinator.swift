//
//  AppRuntimeCoordinator.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI

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
    private var state: RuntimeState = .idle
    private var lastPressDate: Date = .distantPast
    private let minimumPressInterval: TimeInterval = 0.30

    func start() {
        guard hotKeyMonitor == nil else {
            return
        }

        hotKeyMonitor = GlobalHotKeyMonitor { [weak self] in
            self?.handleShortcutPress()
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

    private func beginListening() {
        do {
            try recordingService.startRecording()
            state = .listening
            indicator.show(message: "Listening…", tint: .green)
        } catch {
            let message = errorMessage(for: error)
            indicator.show(message: message, tint: .red, autoHideAfter: 1.8)
        }
    }

    private func finishListeningAndProcess() async {
        guard state == .listening else {
            return
        }

        state = .processing
        indicator.show(message: "Processing…", tint: .orange)

        do {
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
            indicator.show(message: "No speech recognized", tint: .red, autoHideAfter: 1.4)
            return
        }

        let didPaste = pasteService.paste(cleanedTranscript)
        guard didPaste else {
            indicator.show(message: "Paste failed (check Accessibility)", tint: .red, autoHideAfter: 1.8)
            return
        }

        indicator.show(message: "Pasted", tint: .blue, autoHideAfter: 1.0)
    }

    private func handleProcessingFailure(_ error: Error) {
        let message = errorMessage(for: error)
        indicator.show(message: message, tint: .red, autoHideAfter: 1.8)
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
