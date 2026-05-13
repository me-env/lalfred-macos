import SwiftUI

struct BringYourOwnKeySection: View {
  @Bindable var manager: APIKeyViewModel
  let isLoadingAuthURL: Bool
  let onContinueWithGoogle: () async -> Void

  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false
  @AppStorage(AppDefaultsKey.accountIsSubscribed) private var accountIsSubscribed = false
  @State private var accessTip: APIKeyAccessTip?

  private var isSubscribed: Bool {
    isSignedIn && accountIsSubscribed
  }

  private var caption: String {
    isSubscribed
      ? "Stored in secure keychain on this Mac."
      : "Requires an active subscription."
  }
  
  var keysList: some View {
    VStack(spacing: 0) {
      ForEach(Array(APIKeyProvider.allCases.enumerated()), id: \.element.id) { index, provider in
        APIKeyProviderRow(
          provider: provider,
          keySuffix: manager.keySuffix(for: provider),
          onEdit: { beginEditingIfAllowed(provider) },
          onDelete: { manager.delete(provider) }
        )

        if index < APIKeyProvider.allCases.count - 1 {
          Divider()
            .padding(.vertical, 8)
        }
      }
    }
  }

  var body: some View {
    SectionBoxWithTitle("Bring your own keys", caption: caption) {
      VStack(alignment: .leading, spacing: 10) {
        if let accessTip {
          APIKeyAccessTipView(
            tip: accessTip,
            isLoadingAuthURL: isLoadingAuthURL,
            onContinueWithGoogle: onContinueWithGoogle
          )
        }
        keysList
          .id(manager.refreshToken)
      }
    }
    .onChange(of: isSignedIn) { _, _ in
      clearAccessErrorIfAllowed()
    }
    .onChange(of: accountIsSubscribed) { _, _ in
      clearAccessErrorIfAllowed()
    }
    .sheet(item: $manager.editingProvider) { provider in
      APIKeyEditorSheet(
        providerName: provider.displayName,
        onCancel: { manager.cancelEditing() },
        onSave: { apiKey in manager.save(apiKey, for: provider) }
      )
    }
  }

  private func beginEditingIfAllowed(_ provider: APIKeyProvider) {
    guard isSignedIn else {
      accessTip = .signedOut
      return
    }

    guard accountIsSubscribed else {
      accessTip = .notSubscribed
      return
    }

    accessTip = nil
    manager.beginEditing(provider)
  }

  private func clearAccessErrorIfAllowed() {
    if isSubscribed {
      accessTip = nil
    }
  }
}

#Preview {
  BringYourOwnKeySection(
    manager: APIKeyViewModel(),
    isLoadingAuthURL: false,
    onContinueWithGoogle: {}
  )
  .padding()
  .frame(width: 560)
}
