import SwiftUI

struct BringYourOwnKeySection: View {
  @Bindable var manager: APIKeyViewModel
  
  var keysList: some View {
    VStack(spacing: 0) {
      ForEach(Array(APIKeyProvider.allCases.enumerated()), id: \.element.id) { index, provider in
        APIKeyProviderRow(
          provider: provider,
          keySuffix: manager.keySuffix(for: provider),
          onEdit: { manager.beginEditing(provider) },
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
    SectionBoxWithTitle("Bring your own keys", caption: "Stored in secure keychain on this Mac.") {
      keysList
        .id(manager.refreshToken)
    }
    .sheet(item: $manager.editingProvider) { provider in
      APIKeyEditorSheet(
        providerName: provider.displayName,
        onCancel: { manager.cancelEditing() },
        onSave: { apiKey in manager.save(apiKey, for: provider) }
      )
    }
  }
}

#Preview {
  BringYourOwnKeySection(manager: APIKeyViewModel())
  .padding()
  .frame(width: 560)
}
