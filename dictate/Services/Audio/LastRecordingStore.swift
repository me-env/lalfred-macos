import Foundation

/// Keeps the last recording in memory for a while, so its transcription can be retried.
@MainActor
final class LastRecordingStore {
  private static let retention: Duration = .seconds(15 * 60)

  private(set) var audio: Data?
  private var expiryTask: Task<Void, Never>?

  func save(_ audio: Data) {
    guard !audio.isEmpty else { return }

    self.audio = audio
    expiryTask?.cancel()
    expiryTask = Task { [weak self] in
      try? await Task.sleep(for: Self.retention)
      guard !Task.isCancelled else { return }
      self?.audio = nil
    }
  }
}
