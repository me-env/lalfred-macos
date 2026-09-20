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

      BringYourOwnKeySection(
        manager: apiKeyManager,
        isLoadingAuthURL: model.isLoadingAuthURL,
        onContinueWithGoogle: {
          await model.startGoogleOAuth()
        }
      )
    }
    .padding([.bottom, .horizontal])
    .task(id: isSignedIn) {
      await model.handleSignedInChange(isSignedIn: isSignedIn)
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
