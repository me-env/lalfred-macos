import SwiftUI

/// Coordinator for the Account tab. Owns the per-tab view models and composes
/// the three sections: signed-in/signed-out card, redeem-a-code (when signed
/// in), and the BYOK section.
struct AccountTabView: View {
  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false

  @State private var model: AccountTabViewModel
  @State private var apiKeyManager: APIKeyManager
  @State private var redeemModel: RedeemClaimViewModel

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

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
    _apiKeyManager = State(initialValue: APIKeyManager())
    _redeemModel = State(initialValue: RedeemClaimViewModel())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isSignedIn {
        ConnectedAccountCard(model: model)
        RedeemClaimSection(model: redeemModel)
      } else {
        LoggedOutCard(model: model)
      }

      BringYourOwnKeySection(manager: apiKeyManager)
    }
    .padding()
    .task(id: isSignedIn) {
      await model.handleSignedInChange(isSignedIn: isSignedIn)
      apiKeyManager.refresh()
      consumePendingDeepLinkKey()
    }
    .onAppear {
      consumePendingDeepLinkKey()
    }
    .onChange(of: deepLinkCoordinator.pendingKey) { _, _ in
      consumePendingDeepLinkKey()
    }
    .sheet(item: redeemSuccessBinding) { success in
      RedeemSuccessSheet(success: success) {
        redeemModel.dismissSuccess()
      }
    }
  }

  /// If a redemption key arrived via deep link while we were elsewhere, push
  /// it into the redeem field (only when the user is signed in — otherwise we
  /// keep it pending until after sign-in).
  private func consumePendingDeepLinkKey() {
    guard isSignedIn, let key = deepLinkCoordinator.pendingKey else { return }
    redeemModel.inputKey = key
    deepLinkCoordinator.clearPending()
  }

  /// Bridges `lastSuccess: RedeemClaimSuccess?` into a `Binding<Item?>` for
  /// `.sheet(item:)`. The `Item` must conform to `Identifiable`, so we wrap.
  private var redeemSuccessBinding: Binding<IdentifiedSuccess?> {
    Binding(
      get: {
        redeemModel.lastSuccess.map { IdentifiedSuccess(value: $0) }
      },
      set: { newValue in
        if newValue == nil {
          redeemModel.dismissSuccess()
        }
      }
    )
  }
}

private struct IdentifiedSuccess: Identifiable {
  let value: RedeemClaimSuccess
  let id = UUID()
}

private extension RedeemSuccessSheet {
  init(success identifiable: IdentifiedSuccess, onDismiss: @escaping () -> Void) {
    self.init(success: identifiable.value, onDismiss: onDismiss)
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
