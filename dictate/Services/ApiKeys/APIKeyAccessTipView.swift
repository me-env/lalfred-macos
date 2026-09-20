import SwiftUI


struct APIKeyAccessTipView: View {
  let isLoadingAuthURL: Bool
  let onContinueWithGoogle: () async -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.tint)

      VStack(alignment: .leading, spacing: 8) {
        Text("Sign in to add your own API key.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Button(isLoadingAuthURL ? "Opening Google..." : "Continue with Google") {
          Task {
            await onContinueWithGoogle()
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isLoadingAuthURL)
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

#Preview("Signed Out") {
  APIKeyAccessTipView(
    isLoadingAuthURL: false,
    onContinueWithGoogle: {}
  )
  .padding()
  .frame(width: 420)
}
