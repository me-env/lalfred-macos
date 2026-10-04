import Foundation
import Observation


/// The latest check of each saved API key, shared by the Account tab and its sidebar badge.
@MainActor
@Observable
final class APIKeyHealth {
  static let shared = APIKeyHealth()

  private(set) var states: [APIKeyProvider: APIKeyValidationState] = [:]
  @ObservationIgnored private var checks: [APIKeyProvider: Task<Void, Never>] = [:]

  /// True when a saved key was rejected by its provider.
  var hasProblem: Bool {
    states.values.contains { state in
      if case .done(.invalid) = state { return true }
      return false
    }
  }

  func state(for provider: APIKeyProvider) -> APIKeyValidationState {
    states[provider] ?? .idle
  }

  func checkAll() {
    APIKeyProvider.allCases.forEach(check)
  }

  /// Checks the saved key again; a newer check replaces one still in flight.
  func check(_ provider: APIKeyProvider) {
    checks[provider]?.cancel()
    states[provider] = .checking
    checks[provider] = Task {
      let result = await APIKeyValidator.validateSavedKey(for: provider)
      guard !Task.isCancelled else { return }
      states[provider] = result.map { .done($0) } ?? .idle
    }
  }
}
