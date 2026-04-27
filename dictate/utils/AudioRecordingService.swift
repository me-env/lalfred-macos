//
//  AudioRecordingService.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation
import AVFoundation

final class AudioRecordingService: NSObject {
    enum RecordingError: LocalizedError {
        case microphonePermissionMissing
        case alreadyRecording
        case failedToCreateRecorder
        case notRecording
        case failedToFinalizeRecording

        var errorDescription: String? {
            switch self {
            case .microphonePermissionMissing:
                return "Microphone permission is not granted"
            case .alreadyRecording:
                return "A recording is already in progress"
            case .failedToCreateRecorder:
                return "Failed to create audio recorder"
            case .notRecording:
                return "No active recording"
            case .failedToFinalizeRecording:
                return "Failed to finalize audio recording"
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var activeFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func startRecording() throws {
        try ensureMicrophonePermission()
        try ensureNotRecording()

        let fileURL = makeRecordingFileURL()
        let nextRecorder = try makeRecorder(fileURL: fileURL)

        guard nextRecorder.record() else {
            throw RecordingError.failedToCreateRecorder
        }

        recorder = nextRecorder
        activeFileURL = fileURL
    }

    func stopRecording() async throws -> URL {
        guard let recorder, recorder.isRecording else {
            throw RecordingError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            recorder.stop()
        }
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil

        if let activeFileURL {
            try? FileManager.default.removeItem(at: activeFileURL)
        }

        activeFileURL = nil

        if let stopContinuation {
            self.stopContinuation = nil
            stopContinuation.resume(throwing: RecordingError.failedToFinalizeRecording)
        }
    }

    private func ensureMicrophonePermission() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw RecordingError.microphonePermissionMissing
        }
    }

    private func ensureNotRecording() throws {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }
    }

    private func makeRecordingFileURL() -> URL {
        let filename = "dictate-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func makeRecorder(fileURL: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVNumberOfChannelsKey: 1
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()
        return recorder
    }

    private func finishRecording(successfully: Bool) {
        guard let continuation = stopContinuation else {
            return
        }

        stopContinuation = nil

        guard successfully, let activeFileURL else {
            continuation.resume(throwing: RecordingError.failedToFinalizeRecording)
            recorder = nil
            return
        }

        continuation.resume(returning: activeFileURL)
        recorder = nil
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        finishRecording(successfully: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let stopContinuation {
            self.stopContinuation = nil
            stopContinuation.resume(throwing: error ?? RecordingError.failedToFinalizeRecording)
        }

        self.recorder = nil
    }
}
