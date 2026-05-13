import SwiftUI

/// Celebration sheet shown after a redeem call succeeds. Layers confetti
/// behind a card that summarises what was applied to the user's account.
struct RedeemSuccessSheet: View {
  let success: RedeemClaimSuccess
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.clear
        .background(Material.regular)

      ConfettiView()

      VStack(spacing: 18) {
        Image(systemName: "sparkles")
          .font(.system(size: 36, weight: .semibold))
          .foregroundStyle(.yellow)

        Text("Thank you for purchasing!")
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)

        summary
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .padding(.horizontal)

        Button("Done") {
          onDismiss()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(28)
      .frame(maxWidth: 360)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor))
          .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
      )
    }
    .frame(width: 460, height: 320)
  }

  @ViewBuilder
  private var summary: some View {
    switch success.kind {
    case .credits:
      if let added = success.creditsAdded {
        Text("**\(added.formatted(.number.grouping(.automatic))) credits** were added to your L'Alfred account.")
      } else {
        Text("Credits were added to your L'Alfred account.")
      }
    case .subscription:
      if let endsAt = success.subscriptionEndsAt {
        Text("Your subscription is active until **\(endsAt.formatted(date: .abbreviated, time: .omitted))**.")
      } else {
        Text("Your subscription is now active.")
      }
    }
  }
}

#Preview("Credits success") {
  RedeemSuccessSheet(
    success: RedeemClaimSuccess(
      kind: .credits,
      creditsAdded: 88_000,
      subscriptionStartsAt: nil,
      subscriptionEndsAt: nil,
    ),
    onDismiss: {},
  )
}

#Preview("Subscription success") {
  RedeemSuccessSheet(
    success: RedeemClaimSuccess(
      kind: .subscription,
      creditsAdded: nil,
      subscriptionStartsAt: Date(),
      subscriptionEndsAt: Date().addingTimeInterval(60 * 60 * 24 * 30),
    ),
    onDismiss: {},
  )
}
