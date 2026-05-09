import SwiftUI

struct LoggedOutCard: View {
  let model: AccountTabViewModel

  @AppStorage(AppDefaultsKey.signupBonusCredits) private var signupBonusCredits: Int = 0

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Sign in to your account")
          .font(.title3.weight(.semibold))

        Text(introMessage)
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
    .task {
      await SignupBonusFetcher.refresh()
    }
  }

  private var introMessage: String {
    if signupBonusCredits > 0 {
      let formatted = signupBonusCredits.formatted(.number.grouping(.automatic))
      return "Sign in to claim \(formatted) free credits and start dictating right away. Credits are used for speech-to-text and LLM processing."
    }
    return "Logging in lets you purchase credits that this app uses for speech-to-text transcription and LLM processing."
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
