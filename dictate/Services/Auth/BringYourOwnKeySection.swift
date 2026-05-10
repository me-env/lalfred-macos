import SwiftUI

struct BringYourOwnKeySection: View {
  @Bindable var manager: APIKeyManager
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
      ? "Stored in app defaults on this Mac."
      : "Requires an active subscription."
  }

  var body: some View {
    SectionBoxWithTitle("Bring your own key", caption: caption) {
      VStack(alignment: .leading, spacing: 10) {
        if let accessTip {
          APIKeyAccessTipView(
            tip: accessTip,
            isLoadingAuthURL: isLoadingAuthURL,
            onContinueWithGoogle: onContinueWithGoogle
          )
        }

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
    }
    .onAppear {
      manager.refresh()
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
        beginEditingIfAllowed(provider)
      }
      .buttonStyle(.borderedProminent)

      if hasKey {
        Button("Delete", role: .destructive) {
          manager.delete(provider)
        }
        .buttonStyle(.bordered)
      }
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

private enum APIKeyAccessTip {
  case signedOut
  case notSubscribed

  var message: String {
    switch self {
    case .signedOut:
      return "Sign in and subscribe to add your own API key."
    case .notSubscribed:
      return "Your own API key is available with an active subscription."
    }
  }
}

private struct APIKeyAccessTipView: View {
  let tip: APIKeyAccessTip
  let isLoadingAuthURL: Bool
  let onContinueWithGoogle: () async -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.tint)

      VStack(alignment: .leading, spacing: 8) {
        Text(tip.message)
          .font(.caption)
          .foregroundStyle(.secondary)

        switch tip {
        case .signedOut:
          Button(isLoadingAuthURL ? "Opening Google..." : "Continue with Google") {
            Task {
              await onContinueWithGoogle()
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(isLoadingAuthURL)
        case .notSubscribed:
          Link("View pricing", destination: URL(string: "https://lalfred.ai/#pricing")!)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.tint.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.tint.opacity(0.16), lineWidth: 1)
    )
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
