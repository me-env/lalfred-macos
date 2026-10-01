import Foundation


enum TranscriptionRetryPolicy {
  static let autoRetryDelay: Duration = .seconds(1)

  static var isAutoRetryEnabled: Bool {
    UserDefaults.standard.bool(forKey: AppDefaultsKey.autoRetryFailedTranscription)
  }

  /// Network failures and server-side errors are worth retrying; client errors (bad key, bad request) are not.
  static func isTransient(_ error: Error) -> Bool {
    switch error {
    case let urlError as URLError:
      return urlError.code != .cancelled
    case let ScribeError.requestFailed(statusCode, _):
      return statusCode == 429 || statusCode >= 500
    case let ScribeError.realtimeFailed(type, _):
      return ["rate_limited", "queue_overflow", "resource_exhausted", "transcriber_error"].contains(type)
    default:
      return false
    }
  }
}
