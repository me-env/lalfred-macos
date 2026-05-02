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

  @State private var configuredKeySuffixes: [APIKeyProvider: String] = [:]
  @State private var editingProvider: APIKeyProvider?
  @State private var pendingAPIKey = ""

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

      bringYourOwnKeySection
    }
    .padding()
    .task(id: isSignedIn) {
      await handleAuthStateChange()
      refreshAPIKeyStatuses()
    }
    .onAppear {
      refreshAPIKeyStatuses()
    }
    .sheet(item: $editingProvider) { provider in
      APIKeyEditorSheet(
        providerName: provider.displayName,
        apiKey: $pendingAPIKey,
        onCancel: {
          editingProvider = nil
          pendingAPIKey = ""
        },
        onSave: {
          saveAPIKey(for: provider)
        }
      )
    }
  }

  private var tabBackground: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color(nsColor: .controlBackgroundColor))
      .stroke(Color.primary.opacity(0.08), lineWidth: 1)
  }

  private var loggedOutCard: some View {
    HStack {
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
      Spacer()
    }
    .padding()
    .background(tabBackground)
  }

  private var connectedAccountCard: some View {
    VStack(alignment: .leading) {
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
        .padding(.vertical, 4)

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
    .background(tabBackground)
  }

  private var bringYourOwnKeySection: some View {
    SectionBox("Bring your own key", caption: "Stored securely in your macOS Keychain.") {
      VStack(spacing: 0) {
        ForEach(Array(APIKeyProvider.allCases.enumerated()), id: \.element.id) { index, provider in
          keyProviderRow(provider)

          if index < APIKeyProvider.allCases.count - 1 {
            Divider()
              .padding(.vertical, 8)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func keyProviderRow(_ provider: APIKeyProvider) -> some View {
    let keySuffix = configuredKeySuffixes[provider]
    let hasKey = keySuffix != nil

    HStack(spacing: 12) {
      Image(systemName: hasKey ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(hasKey ? .green : .secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(provider.displayName)
          .font(.subheadline.weight(.semibold))

        Text(hasKey ? "Key set (•••• \(keySuffix!))" : "No key configured")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(hasKey ? "Update key" : "Set key") {
        beginEditing(provider)
      }
      .buttonStyle(.borderedProminent)

      if hasKey {
        Button("Delete", role: .destructive) {
          deleteKey(for: provider)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var accountDisplayName: String {
    let first = trimmedAccountFirstName
    let last = trimmedAccountLastName
    let fullName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    return fullName.isEmpty ? "Account" : fullName
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
    isLoadingAccountDetails && accountDisplayName == "Account"
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

  private func refreshAPIKeyStatuses() {
    var suffixes: [APIKeyProvider: String] = [:]

    for provider in APIKeyProvider.allCases {
      guard let key = apiKeyStore(for: provider).load() else {
        continue
      }

      let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        continue
      }

      suffixes[provider] = String(trimmed.suffix(4))
    }

    configuredKeySuffixes = suffixes
  }

  private func beginEditing(_ provider: APIKeyProvider) {
    pendingAPIKey = apiKeyStore(for: provider).load() ?? ""
    editingProvider = provider
  }

  private func saveAPIKey(for provider: APIKeyProvider) {
    let trimmed = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    apiKeyStore(for: provider).save(trimmed)
    configuredKeySuffixes[provider] = String(trimmed.suffix(4))
    editingProvider = nil
    pendingAPIKey = ""
  }

  private func deleteKey(for provider: APIKeyProvider) {
    apiKeyStore(for: provider).remove()
    configuredKeySuffixes[provider] = nil
  }

  private func apiKeyStore(for provider: APIKeyProvider) -> APIKeyDefaultsStore {
    APIKeyDefaultsStore(key: provider.defaultsKey)
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

private enum APIKeyProvider: String, CaseIterable, Identifiable {
  case elevenLabs
  case openAI

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .elevenLabs:
      return "ElevenLabs"
    case .openAI:
      return "OpenAI"
    }
  }

  var defaultsKey: String {
    switch self {
    case .elevenLabs:
      return AppDefaultsKey.apiKeyElevenLabs
    case .openAI:
      return AppDefaultsKey.apiKeyOpenAI
    }
  }
}

private struct APIKeyEditorSheet: View {
  let providerName: String
  @Binding var apiKey: String
  let onCancel: () -> Void
  let onSave: () -> Void

  private var trimmedKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Set \(providerName) API key")
        .font(.headline)

      Text("Paste your key below, then confirm.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      SecureField("Enter API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)

      HStack {
        Spacer()

        Button("Cancel", role: .cancel) {
          onCancel()
        }

        Button("OK") {
          onSave()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(trimmedKey.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
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

