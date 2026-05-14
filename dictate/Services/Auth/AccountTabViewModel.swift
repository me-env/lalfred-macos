import AppKit
import Foundation
import Observation
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "AccountTabViewModel")

/// Owns the transient state (loading flags, error messages) and actions for the
/// Account tab. Persistent values (email, credits, isSignedIn) continue to live
/// in `UserDefaults` and are read directly from the views via `@AppStorage`.
@MainActor
@Observable
final class AccountTabViewModel {
  var isLoadingAuthURL: Bool
  var authErrorMessage: String

  var isLoadingAccountDetails: Bool = false
  var accountDetailsErrorMessage: String = ""

  @ObservationIgnored private let authManager: AuthManager

  init(
    initialIsLoadingAuthURL: Bool = false,
    initialAuthErrorMessage: String = ""
  ) {
    self.authManager = .shared
    self.isLoadingAuthURL = initialIsLoadingAuthURL
    self.authErrorMessage = initialAuthErrorMessage
  }

  // MARK: - Sign-in

  func startGoogleOAuth() async {
    isLoadingAuthURL = true
    authErrorMessage = ""
    defer { isLoadingAuthURL = false }

    do {
      let googleOAuthURL = try await authManager.fetchGoogleAuthorizationURL()
      NSWorkspace.shared.open(googleOAuthURL)
    } catch {
      authErrorMessage = errorMessage(
        from: error,
        fallback: "Failed to start Google sign-in."
      )
    }
  }

  // MARK: - Account details

  /// Reacts to `isSignedIn` flips. Caller wires this up via `.task(id: isSignedIn)`.
  func handleSignedInChange(isSignedIn: Bool) async {
    logger.info("handleSignedInChange isSignedIn=\(isSignedIn)")
    guard isSignedIn else {
      isLoadingAccountDetails = false
      accountDetailsErrorMessage = ""
      return
    }

    guard !isRunningInPreview else { return }

    await loadAccountDetails()
  }

  func loadAccountDetails() async {
    logger.info("loadAccountDetails isLoadingAccountDetails=\(self.isLoadingAccountDetails)")
    guard !isLoadingAccountDetails else { return }

    isLoadingAccountDetails = true
    accountDetailsErrorMessage = ""
    defer { isLoadingAccountDetails = false }

    do {
      try await authManager.refreshAccountDetails()
    } catch {
      logger.error("Error while fetching account details \(error)")
      accountDetailsErrorMessage = errorMessage(
        from: error,
        fallback: "Failed to load account details."
      )
    }
  }

  // MARK: - Sign-out

  func signOut() {
    authManager.signOutAndResetPreferences()
    authErrorMessage = ""
    accountDetailsErrorMessage = ""
    isLoadingAccountDetails = false
  }

  // MARK: - Helpers

  private func errorMessage(from error: Error, fallback: String) -> String {
    if let localized = error as? LocalizedError,
       let message = localized.errorDescription,
       !message.isEmpty {
      return message
    }
    return fallback
  }

  private var isRunningInPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }
}
