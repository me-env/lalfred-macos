import Foundation


/// Errors from the transcription providers, worded for the indicator.
nonisolated enum TranscriptionError: LocalizedError {
  case missingAPIKey(APIKeyProvider)
  case invalidResponse(APIKeyProvider)
  case requestFailed(APIKeyProvider, statusCode: Int, message: String?)

  var errorDescription: String? {
    switch self {
    case let .missingAPIKey(provider):
      return "Missing \(provider.displayName) API key"
    case let .invalidResponse(provider):
      return "Unexpected response from \(provider.displayName)"
    case let .requestFailed(provider, statusCode, message):
      return Self.requestFailedDescription(provider.displayName, statusCode: statusCode, message: message)
    }
  }

  /// Rate limits and server-side failures are worth retrying; bad keys and bad requests are not.
  var isTransient: Bool {
    switch self {
    case .missingAPIKey, .invalidResponse:
      return false
    case let .requestFailed(_, statusCode, _):
      return statusCode == 429 || statusCode >= 500
    }
  }

  private static func requestFailedDescription(_ provider: String, statusCode: Int, message: String?) -> String {
    switch statusCode {
    case 401:
      // Some providers also answer 401 for an exhausted quota, so their message is kept when there is one.
      return message.map { "\(provider) rejected the API key: \($0)" } ?? "Invalid \(provider) API key"
    case 429:
      return "\(provider) rate limit reached, try again shortly"
    case 500...:
      return "\(provider) is unavailable (\(statusCode))"
    default:
      return message.map { "\(provider) request failed (\(statusCode)): \($0)" } ?? "\(provider) request failed (\(statusCode))"
    }
  }
}

/// Reads the human-readable message out of a provider's error body.
nonisolated enum ServerErrorMessage {
  private static let maxLength = 200

  /// Handles `message`, `detail`, `error` and `msg`, as strings, nested objects or lists, and falls back on the raw body.
  static func parse(_ data: Data) -> String? {
    if let json = try? JSONSerialization.jsonObject(with: data), let message = findMessage(in: json) {
      return String(message.prefix(maxLength))
    }

    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : String(text.prefix(maxLength))
  }

  private static func findMessage(in value: Any?) -> String? {
    switch value {
    case let text as String:
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case let list as [Any]:
      return list.lazy.compactMap { findMessage(in: $0) }.first
    case let object as [String: Any]:
      return ["message", "detail", "error", "msg"].lazy.compactMap { findMessage(in: object[$0]) }.first
    default:
      return nil
    }
  }
}
