import SwiftUI

struct APIKeyProviderRow: View {
  let provider: APIKeyProvider
  let keySuffix: String?
  let onEdit: () -> Void
  let onDelete: () -> Void

  private var hasKey: Bool {
    keySuffix != nil
  }

  var body: some View {
    HStack(spacing: 12) {
      statusIcon
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(provider.displayName)
          .font(.subheadline.weight(.semibold))

        Text(keyStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(hasKey ? "Update key" : "Set key") {
        onEdit()
      }
      .buttonStyle(.borderedProminent)

      if hasKey {
        Button("Delete", role: .destructive) {
          onDelete()
        }
        .buttonStyle(.bordered)
      }
    }
  }

  /// A key that couldn't be checked (offline, server error) keeps the plain "set" checkmark.
  @ViewBuilder
  private var statusIcon: some View {
    if !hasKey {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.secondary)
    } else {
      switch APIKeyHealth.shared.state(for: provider) {
      case .idle, .checking:
        ProgressView()
          .controlSize(.small)
      case .done(.invalid):
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
          .help("Key rejected by \(provider.displayName)")
      case .done(.valid), .done(.unknown):
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
  }

  private var keyStatusText: String {
    if let keySuffix {
      return "Key set (•••• \(keySuffix))"
    }

    return "No key configured"
  }
}

#Preview {
  VStack(spacing: 0) {
    APIKeyProviderRow(
      provider: .elevenLabs,
      keySuffix: "1234",
      onEdit: {},
      onDelete: {}
    )
  }
  .padding()
  .frame(width: 520)
}
