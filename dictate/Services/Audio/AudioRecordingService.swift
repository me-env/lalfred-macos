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
        return "No microphone device detected"
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
  private var meteringTimer: Timer?
  
  var onAudioLevelUpdate: ((Float) -> Void)?
  
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
    startMeteringUpdates()
  }
  
  func stopRecording() async throws -> URL {
    guard let recorder, recorder.isRecording else {
      throw RecordingError.notRecording
    }
    
    stopMeteringUpdates()
    
    return try await withCheckedThrowingContinuation { continuation in
      stopContinuation = continuation
      recorder.stop()
    }
  }
  
  func cancelRecording() {
    stopMeteringUpdates()
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
    let filename = "lalfred-\(UUID().uuidString).m4a"
    return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
  }
  
  private func makeRecorder(fileURL: URL) throws -> AVAudioRecorder {
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16_000,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
      AVEncoderBitRateKey: 32_000,
      AVNumberOfChannelsKey: 1
    ]
    
    let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
    recorder.delegate = self
    recorder.isMeteringEnabled = true
    recorder.prepareToRecord()
    return recorder
  }
  
  private func startMeteringUpdates() {
    stopMeteringUpdates()
    
    meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.publishAudioLevel()
    }
  }
  
  private func stopMeteringUpdates() {
    meteringTimer?.invalidate()
    meteringTimer = nil
  }
  
  private func publishAudioLevel() {
    guard let recorder, recorder.isRecording else { return }
    
    recorder.updateMeters()
    let averagePower = recorder.averagePower(forChannel: 0)
    let normalizedLevel = normalizeAveragePower(averagePower)
    onAudioLevelUpdate?(normalizedLevel)
  }
  
  private func normalizeAveragePower(_ averagePower: Float) -> Float {
    let minimumDecibels: Float = -50
    if averagePower <= minimumDecibels { return 0 }
    if averagePower >= 0 { return 1 }
    return (averagePower - minimumDecibels) / -minimumDecibels
  }
  
  private func finishRecording(successfully: Bool) {
    stopMeteringUpdates()
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
