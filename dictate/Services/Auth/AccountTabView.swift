import SwiftUI
import AppKit

struct AccountTabView: View {
  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false
  @AppStorage(AppDefaultsKey.accountEmail) private var accountEmail = ""
  @AppStorage(AppDefaultsKey.accountFirstName) private var accountFirstName = ""
  @AppStorage(AppDefaultsKey.accountLastName) private var accountLastName = ""
  @AppStorage(AppDefaultsKey.accountCredits) private var accountCredits = -1
  
  @State private var isLoadingAuthURL = false
  @State private var isLoadingAccountDetails = false
  @State private var authErrorMessage = ""
  @State private var accountDetailsErrorMessage = ""

  init(
    initialIsLoadingAuthURL: Bool = false,
    initialAuthErrorMessage: String = ""
  ) {
    _isLoadingAuthURL = State(initialValue: initialIsLoadingAuthURL)
    _authErrorMessage = State(initialValue: initialAuthErrorMessage)
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isSignedIn {
        connectedAccountCard
      } else {
        loggedOutCard
      }
    }
    .padding()
    .task(id: isSignedIn) {
      await handleAuthStateChange()
    }
  }
  
  private var loggedOutCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Sign in to your account")
        .font(.title3.weight(.semibold))

      Text("Logging in lets you purchase credits that this app uses for speech-to-text transcription and LLM processing.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Link("More details: lalfred.ai/#pricing", destination: URL(string: "https://lalfred.ai/#pricing")!)
        .font(.subheadline)

      Button(isLoadingAuthURL ? "Opening Google..." : "Continue with Google") {
        Task {
          await startGoogleOAuth()
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoadingAuthURL)

      if !authErrorMessage.isEmpty {
        Divider()
        Text(authErrorMessage)
          .foregroundStyle(.red)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }

  private var connectedAccountCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      if isLoadingAccountName {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading account details...")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      } else {
        Text(accountDisplayName)
          .font(.title3.weight(.semibold))
      }

      if isLoadingAccountEmail {
        Text("Loading email...")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .redacted(reason: .placeholder)
      } else {
        Text(accountEmail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Divider()

      HStack(alignment: .center) {
        if isLoadingCredits {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Loading credits...")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }
        } else {
          Text(creditsLabel)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
        }

        Spacer()

        Button("Sign out", role: .destructive) {
          signOut()
        }
        .buttonStyle(.borderless)
      }

      if !accountDetailsErrorMessage.isEmpty {
        Text(accountDetailsErrorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }
  
  private var accountDisplayName: String {
    let first = trimmedAccountFirstName
    let last = trimmedAccountLastName
    return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
  }

  private var trimmedAccountFirstName: String {
    accountFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedAccountLastName: String {
    accountLastName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedAccountEmail: String {
    accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isLoadingAccountName: Bool {
    isLoadingAccountDetails && accountDisplayName.isEmpty
  }

  private var isLoadingAccountEmail: Bool {
    isLoadingAccountDetails && trimmedAccountEmail.isEmpty
  }

  private var isLoadingCredits: Bool {
    isLoadingAccountDetails && accountCredits < 0
  }

  private var hasLoadedCredits: Bool {
    accountCredits >= 0
  }

  private var creditsLabel: String {
    if hasLoadedCredits {
      return "\(formattedCredits) credits"
    }

    return "Credits unavailable"
  }

  private var formattedCredits: String {
    max(0, accountCredits).formatted(.number.grouping(.automatic))
  }
  
  private func startGoogleOAuth() async {
    isLoadingAuthURL = true
    authErrorMessage = ""
    defer { isLoadingAuthURL = false }

    do {
      let googleOAuthURL = try await AuthManager.shared.fetchGoogleAuthorizationURL()
      NSWorkspace.shared.open(googleOAuthURL)
    } catch {
      if let localizedError = error as? LocalizedError,
         let message = localizedError.errorDescription,
         !message.isEmpty {
        authErrorMessage = message
      } else {
        authErrorMessage = "Failed to start Google sign-in."
      }
    }
  }

  private func handleAuthStateChange() async {
    guard isSignedIn else {
      isLoadingAccountDetails = false
      accountDetailsErrorMessage = ""
      return
    }

    guard !isRunningInPreview else {
      return
    }

    await loadAccountDetails()
  }

  private func loadAccountDetails() async {
    guard !isLoadingAccountDetails else {
      return
    }

    isLoadingAccountDetails = true
    accountDetailsErrorMessage = ""
    defer { isLoadingAccountDetails = false }

    do {
      try await AuthManager.shared.refreshAccountDetails()
    } catch {
      if let localizedError = error as? LocalizedError,
         let message = localizedError.errorDescription,
         !message.isEmpty {
        accountDetailsErrorMessage = message
      } else {
        accountDetailsErrorMessage = "Failed to load account details."
      }
    }
  }
  
  private var isRunningInPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  private func signOut() {
    AuthManager.shared.signOutAndResetPreferences()
    authErrorMessage = ""
    accountDetailsErrorMessage = ""
    isLoadingAccountDetails = false
  }
}

private struct AccountTabPreviewContainer: View {
  private let isSignedIn: Bool
  private let authErrorMessage: String
  private let previewDefaults: UserDefaults

  init(
    isSignedIn: Bool,
    authErrorMessage: String = "",
    accountEmail: String? = nil,
    accountFirstName: String? = nil,
    accountLastName: String? = nil,
    accountCredits: Int? = nil
  ) {
    self.isSignedIn = isSignedIn
    self.authErrorMessage = authErrorMessage

    let suiteName = "preview.accountTab.\(isSignedIn).\(authErrorMessage.hashValue)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(isSignedIn, forKey: AppDefaultsKey.isSignedIn)

    if let accountEmail {
      defaults.set(accountEmail, forKey: AppDefaultsKey.accountEmail)
    }

    if let accountFirstName {
      defaults.set(accountFirstName, forKey: AppDefaultsKey.accountFirstName)
    }

    if let accountLastName {
      defaults.set(accountLastName, forKey: AppDefaultsKey.accountLastName)
    }

    if let accountCredits {
      defaults.set(accountCredits, forKey: AppDefaultsKey.accountCredits)
    }

    self.previewDefaults = defaults
  }

  var body: some View {
    AccountTabView(initialAuthErrorMessage: authErrorMessage)
      .defaultAppStorage(previewDefaults)
  }
}

#Preview("Logged Out: No Error") {
  AccountTabPreviewContainer(isSignedIn: false)
}

#Preview("Logged Out: Localized Error") {
  AccountTabPreviewContainer(
    isSignedIn: false,
    authErrorMessage: "The request timed out. Please check your connection and try again."
  )
}

#Preview("Logged Out: Fallback Error") {
  AccountTabPreviewContainer(
    isSignedIn: false,
    authErrorMessage: "Failed to start Google sign-in."
  )
}

#Preview("Logged In: Loading Data") {
  AccountTabPreviewContainer(isSignedIn: true)
}

#Preview("Logged In: Loaded Data") {
  AccountTabPreviewContainer(
    isSignedIn: true,
    accountEmail: "jane@example.com",
    accountFirstName: "Jane",
    accountLastName: "Doe",
    accountCredits: 1200
  )
}

