import SwiftUI


struct APIKeyEditorSheet: View {
  let provider: APIKeyProvider
  let onCancel: () -> Void
  let onSave: (String) -> Void

  @State private var apiKey = ""
  @State private var validationState = APIKeyValidationState.idle

  private var trimmedKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Set \(provider.displayName) API key")
        .font(.headline)

      Text("Paste your key below, then confirm.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        SecureField("Enter API key", text: $apiKey)
          .textFieldStyle(.roundedBorder)

        validationIndicator
          .frame(width: 16, height: 16)
      }

      HStack {
        Spacer()

        Button("Cancel", role: .cancel) {
          onCancel()
        }

        Button("OK") {
          onSave(trimmedKey)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(trimmedKey.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
    .task(id: trimmedKey) {
      await validate(trimmedKey)
    }
  }

  @ViewBuilder
  private var validationIndicator: some View {
    switch validationState {
    case .idle, .done(.unknown):
      Color.clear
    case .checking:
      ProgressView()
        .controlSize(.small)
        .help("Checking the key with \(provider.displayName)")
    case .done(.valid):
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .help("Key accepted by \(provider.displayName)")
    case .done(.invalid):
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
        .help("Key rejected by \(provider.displayName)")
    }
  }

  /// Waits for typing to settle, then checks the key; a newer key cancels the check in flight.
  private func validate(_ key: String) async {
    validationState = .idle
    guard !key.isEmpty else { return }

    try? await Task.sleep(for: .milliseconds(400))
    guard !Task.isCancelled else { return }

    validationState = .checking
    let result = await APIKeyValidator.validate(key, for: provider)
    guard !Task.isCancelled else { return }
    validationState = .done(result)
  }
}


#Preview {
  APIKeyEditorSheet(
    provider: .elevenLabs,
    onCancel: {},
    onSave: { _ in }
  )
}
