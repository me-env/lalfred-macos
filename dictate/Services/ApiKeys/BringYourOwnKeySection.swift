import SwiftUI

struct BringYourOwnKeySection: View {
  @Bindable var manager: APIKeyViewModel
  let isLoadingAuthURL: Bool
  let onContinueWithGoogle: () async -> Void

  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false
  @State private var showsSignInTip = false

  private var caption: String {
    isSignedIn
      ? "Stored in secure keychain on this Mac."
      : "Requires you to be signed in."
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
        if showsSignInTip {
          APIKeyAccessTipView(
            isLoadingAuthURL: isLoadingAuthURL,
            onContinueWithGoogle: onContinueWithGoogle
          )
        }
        keysList
          .id(manager.refreshToken)
      }
    }
    .onChange(of: isSignedIn) { _, signedIn in
      if signedIn {
        showsSignInTip = false
      }
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
      showsSignInTip = true
      return
    }

    showsSignInTip = false
    manager.beginEditing(provider)
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
