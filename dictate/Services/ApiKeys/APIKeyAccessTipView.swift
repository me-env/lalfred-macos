import SwiftUI


struct APIKeyAccessTipView: View {
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

#Preview("Signed Out") {
  APIKeyAccessTipView(
    tip: .signedOut,
    isLoadingAuthURL: false,
    onContinueWithGoogle: {}
  )
  .padding()
  .frame(width: 420)
}

#Preview("Not Subscribed") {
  APIKeyAccessTipView(
    tip: .notSubscribed,
    isLoadingAuthURL: false,
    onContinueWithGoogle: {}
  )
  .padding()
  .frame(width: 420)
}
