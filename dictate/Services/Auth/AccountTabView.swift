import SwiftUI

/// Coordinator for the Account tab. Owns the per-tab view models and composes
/// the signed-in/signed-out card and the BYOK section.
struct AccountTabView: View {
  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false

  @State private var model: AccountTabViewModel
  @State private var apiKeyManager: APIKeyViewModel

  init(
    initialIsLoadingAuthURL: Bool = false,
    initialAuthErrorMessage: String = ""
  ) {
    _model = State(
      initialValue: AccountTabViewModel(
        initialIsLoadingAuthURL: initialIsLoadingAuthURL,
        initialAuthErrorMessage: initialAuthErrorMessage
      )
    )
    _apiKeyManager = State(initialValue: APIKeyViewModel())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isSignedIn {
        ConnectedAccountCard(model: model)
      } else {
        LoggedOutCard(model: model)
      }

      BringYourOwnKeySection(manager: apiKeyManager)

      DeveloperResetSection()
    }
    .padding([.bottom, .horizontal])
    .task(id: isSignedIn) {
      await model.handleSignedInChange(isSignedIn: isSignedIn)
    }
  }
}

private struct DeveloperResetSection: View {
  @AppStorage(AppDefaultsKey.accountEmail) private var accountEmail = ""
  @State private var isConfirming = false

  var body: some View {
    if developerEmails.contains(accountEmail) {
      SectionBoxWithTitle(
        "Developer",
        caption: "Puts the app back to a first-launch state. Only macOS permissions survive."
      ) {
        Button("Sign out and erase all data", role: .destructive) {
          isConfirming = true
        }
        .confirmationDialog(
          "Erase all local data?",
          isPresented: $isConfirming,
          titleVisibility: .visible
        ) {
          Button("Erase everything", role: .destructive, action: eraseAllLocalData)
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Signs you out and deletes every keyword, snippet, shortcut, sound, API key and preference stored on this Mac. This cannot be undone.")
        }
      }
    }
  }

  private func eraseAllLocalData() {
    Keychain().deleteAll()

    let defaults = UserDefaults.standard
    guard let bundleIdentifier = Bundle.main.bundleIdentifier,
          let domain = defaults.persistentDomain(forName: bundleIdentifier) else {
      return
    }

    // Key by key rather than `removePersistentDomain`, so every `@AppStorage`
    // observing one of them actually sees the change and the UI drops back to
    // onboarding immediately.
    for key in domain.keys {
      defaults.removeObject(forKey: key)
    }
  }
}

// MARK: - Previews

private struct AccountTabPreviewContainer: View {
  private let isSignedIn: Bool
  private let authErrorMessage: String
  private let previewDefaults: UserDefaults

  init(
    isSignedIn: Bool,
    authErrorMessage: String = "",
    accountEmail: String? = nil,
    accountFirstName: String? = nil,
    accountLastName: String? = nil
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
    accountLastName: "Doe"
  )
}
