import SwiftUI

struct LoggedOutCard: View {
  let model: AccountTabViewModel

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Sign in to your account")
          .font(.title3.weight(.semibold))

        Text("Logging in lets you purchase credits that this app uses for speech-to-text transcription and LLM processing.")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Link("More details: lalfred.ai/#pricing", destination: URL(string: "https://lalfred.ai/#pricing")!)
          .font(.subheadline)

        Button(model.isLoadingAuthURL ? "Opening Google..." : "Continue with Google") {
          Task {
            await model.startGoogleOAuth()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoadingAuthURL)

        if deepLinkCoordinator.pendingKey != nil {
          pendingRedeemHint
        }

        if !model.authErrorMessage.isEmpty {
          Divider()
          Text(model.authErrorMessage)
            .foregroundStyle(.red)
        }
      }
      Spacer()
    }
    .accountCardBackground()
  }

  private var pendingRedeemHint: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "ticket.fill")
        .foregroundStyle(.tint)
      Text("Sign in first — your redemption code is ready and will be applied right after.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.tint.opacity(0.08))
    )
  }
}
