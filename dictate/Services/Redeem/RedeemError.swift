import AppKit
import Foundation
import Observation
import OSLog


enum RedeemError: LocalizedError {
  case invalidResponse
  case unauthorized
  case invalidKey
  case alreadyClaimed
  case serverError(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Unexpected server response."
    case .unauthorized:
      return "You need to be signed in to redeem a code."
    case .invalidKey:
      return "We couldn't find that code. Double-check it and try again."
    case .alreadyClaimed:
      return "This code has already been redeemed."
    case let .serverError(status, message):
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? "Server error (\(status)). Please try again later."
        : "Server error (\(status)): \(trimmed)"
    }
  }
}
