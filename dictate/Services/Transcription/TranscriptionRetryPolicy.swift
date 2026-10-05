import Foundation


/// A transcription that fails for a transient reason is retried once, after `autoRetryDelay`.
enum TranscriptionRetryPolicy {
  static let autoRetryDelay: Duration = .seconds(1)

  /// Network failures and server-side errors are worth retrying; client errors (bad key, bad request) are not.
  static func isTransient(_ error: Error) -> Bool {
    switch error {
    case let urlError as URLError:
      return urlError.code != .cancelled
    case let transcriptionError as TranscriptionError:
      return transcriptionError.isTransient
    default:
      return false
    }
  }
}
