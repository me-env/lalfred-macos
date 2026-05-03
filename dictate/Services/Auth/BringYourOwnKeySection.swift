import SwiftUI

struct BringYourOwnKeySection: View {
  @Bindable var manager: APIKeyManager

  @AppStorage(AppDefaultsKey.isSignedIn) private var isSignedIn = false
  @AppStorage(AppDefaultsKey.accountIsSubscribed) private var accountIsSubscribed = false

  private var isSubscribed: Bool {
    isSignedIn && accountIsSubscribed
  }

  private var caption: String {
    isSubscribed
      ? "Stored in app defaults on this Mac."
      : "Requires an active subscription."
  }

  var body: some View {
    SectionBoxWithTitle("Bring your own key", caption: caption) {
      VStack(spacing: 0) {
        ForEach(Array(APIKeyProvider.allCases.enumerated()), id: \.element.id) { index, provider in
          providerRow(provider)

          if index < APIKeyProvider.allCases.count - 1 {
            Divider()
              .padding(.vertical, 8)
          }
        }
      }
    }
    .onAppear {
      manager.refresh()
    }
    .sheet(item: $manager.editingProvider) { provider in
      APIKeyEditorSheet(
        providerName: provider.displayName,
        apiKey: $manager.pendingAPIKey,
        onCancel: { manager.cancelEditing() },
        onSave: { manager.saveCurrent() }
      )
    }
  }

  @ViewBuilder
  private func providerRow(_ provider: APIKeyProvider) -> some View {
    let suffix = manager.keySuffix(for: provider)
    let hasKey = suffix != nil

    HStack(spacing: 12) {
      Image(systemName: hasKey ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(hasKey ? .green : .secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(provider.displayName)
          .font(.subheadline.weight(.semibold))

        Text(hasKey ? "Key set (•••• \(suffix!))" : "No key configured")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(hasKey ? "Update key" : "Set key") {
        manager.beginEditing(provider)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!isSubscribed)

      if hasKey {
        Button("Delete", role: .destructive) {
          manager.delete(provider)
        }
        .buttonStyle(.bordered)
      }
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
