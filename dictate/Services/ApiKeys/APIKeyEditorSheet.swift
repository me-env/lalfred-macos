import SwiftUI


struct APIKeyEditorSheet: View {
  let providerName: String
  let onCancel: () -> Void
  let onSave: (String) -> Void

  @State private var apiKey = ""

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
          onSave(trimmedKey)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(trimmedKey.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
  }
}


#Preview {
  APIKeyEditorSheet(
    providerName: "ElevenLabs",
    onCancel: {},
    onSave: { _ in }
  )
}
