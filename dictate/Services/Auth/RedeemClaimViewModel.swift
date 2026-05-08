import AppKit
import Foundation
import Observation
import OSLog

/// Result of a successful redemption, exposed to the success sheet.
struct RedeemClaimSuccess: Equatable, Sendable {
  enum Kind: String, Sendable {
    case credits
    case subscription
  }

  let kind: Kind
  let creditsAdded: Int?
  let subscriptionStartsAt: Date?
  let subscriptionEndsAt: Date?
}

/// Owns the state of the "Redeem a code" form: the typed/pasted key, the
/// in-flight request, error and success states. Pure-Swift so it's trivially
/// testable; networking is delegated to ``AuthManager`` for auth headers and
/// to ``URLSession`` for transport.
@MainActor
@Observable
final class RedeemClaimViewModel {
  var inputKey: String = ""

  private(set) var isSubmitting: Bool = false
  private(set) var errorMessage: String = ""
  private(set) var lastSuccess: RedeemClaimSuccess?

  @ObservationIgnored private let authManager: AuthManager
  @ObservationIgnored private let urlSession: URLSession
  @ObservationIgnored private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "Redeem")

  init(
    authManager: AuthManager = .shared,
    urlSession: URLSession = .shared
  ) {
    self.authManager = authManager
    self.urlSession = urlSession
  }

  // MARK: - Input helpers

  /// Replaces the input with the system clipboard contents, stripping any
  /// `-` separators copied from the email so the canonical 16-char key remains.
  func pasteFromClipboard() {
    let raw = NSPasteboard.general.string(forType: .string) ?? ""
    inputKey = Self.sanitize(raw)
  }

  /// Normalises a value for transport: trims whitespace and removes `-`.
  static func sanitize(_ raw: String) -> String {
    raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "")
      .uppercased()
  }

  var canSubmit: Bool {
    !isSubmitting && !Self.sanitize(inputKey).isEmpty
  }

  func reset() {
    inputKey = ""
    errorMessage = ""
    lastSuccess = nil
    isSubmitting = false
  }

  // MARK: - Submit

  func submit() async {
    let normalisedKey = Self.sanitize(inputKey)
    guard !normalisedKey.isEmpty else { return }
    guard !isSubmitting else { return }

    isSubmitting = true
    errorMessage = ""
    defer { isSubmitting = false }

    do {
      let success = try await postRedeem(claimKey: normalisedKey)
      lastSuccess = success
      logger.info("redeem ok kind=\(success.kind.rawValue, privacy: .public)")

      // Refresh balance/subscription so the connected account card reflects
      // the new state immediately.
      do {
        try await authManager.refreshAccountDetails()
      } catch {
        logger.error("post-redeem refresh failed: \(error.localizedDescription, privacy: .public)")
      }
    } catch {
      errorMessage = Self.errorMessage(from: error)
      logger.error("redeem failed: \(self.errorMessage, privacy: .public)")
    }
  }

  func dismissSuccess() {
    inputKey = ""
    lastSuccess = nil
  }

  // MARK: - Networking

  private func postRedeem(claimKey: String) async throws -> RedeemClaimSuccess {
    let endpoint = redeemEndpoint()

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    authManager.applyAuthorizationHeader(to: &request)
    request.httpBody = try JSONEncoder().encode(RedeemRequestBody(claim_key: claimKey))

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RedeemError.invalidResponse
    }

    if (200..<300).contains(httpResponse.statusCode) {
      let decoded = try JSONDecoder.lalfred.decode(RedeemResponseBody.self, from: data)
      return decoded.toSuccess()
    }

    let serverMessage = parseServerMessage(from: data)
    switch httpResponse.statusCode {
    case 401, 403:
      throw RedeemError.unauthorized
    case 404:
      throw RedeemError.invalidKey
    case 409:
      throw RedeemError.alreadyClaimed
    default:
      throw RedeemError.serverError(status: httpResponse.statusCode, message: serverMessage)
    }
  }

  private func redeemEndpoint() -> URL {
    APIEndpoints.claimsRedeem
  }

  private func parseServerMessage(from data: Data) -> String {
    if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data),
       !envelope.detail.isEmpty {
      return envelope.detail
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func errorMessage(from error: Error) -> String {
    if let redeemError = error as? RedeemError {
      return redeemError.errorDescription ?? "Failed to redeem the code."
    }
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return error.localizedDescription
  }
}

// MARK: - DTOs

private struct RedeemRequestBody: Encodable {
  let claim_key: String
}

private struct RedeemResponseBody: Decodable {
  let type: String
  let credits_added: Int?
  let subscription_starts_at: Date?
  let subscription_ends_at: Date?

  func toSuccess() -> RedeemClaimSuccess {
    RedeemClaimSuccess(
      kind: type == "subscription" ? .subscription : .credits,
      creditsAdded: credits_added,
      subscriptionStartsAt: subscription_starts_at,
      subscriptionEndsAt: subscription_ends_at,
    )
  }
}

private struct ServerErrorEnvelope: Decodable {
  let detail: String
}

private extension JSONDecoder {
  static let lalfred: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

// MARK: - Errors

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
