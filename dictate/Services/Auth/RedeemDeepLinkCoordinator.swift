import Foundation
import Observation

/// Holds the redemption key parsed from a `lalfred://redeem?key=…` deep link
/// until the Account tab can pick it up. Lives across windows so the key is
/// preserved while the user signs in.
@MainActor
@Observable
final class RedeemDeepLinkCoordinator {
  static let shared = RedeemDeepLinkCoordinator()

  private(set) var pendingKey: String?

  private init() {}

  /// Stores a key from a deep link. Whitespace and dashes are kept here; the
  /// view model is responsible for normalising before posting to the API.
  func setPending(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    pendingKey = trimmed
  }

  /// Called by the Account tab once it has consumed the pending key and pushed
  /// it into its own input state.
  func clearPending() {
    pendingKey = nil
  }
}
