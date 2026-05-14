import SwiftUI


/// One-time onboarding card surfaced in the General tab once the user has
/// completed sign-in plus the microphone & accessibility permissions. The
/// app is `LSUIElement = YES`, so after configuration it lives entirely in
/// the menu bar; this banner makes the transition explicit and tells the
/// user how to reopen the Settings window.
struct BackgroundRunNoticeBanner: View {
  @AppStorage(AppDefaultsKey.hasAcknowledgedBackgroundRunNotice) private var hasAcknowledgedBackgroundRunNotice = false
  private let configuration = AppConfigurationModel.shared

  private var shouldShow: Bool {
    !hasAcknowledgedBackgroundRunNotice && configuration.isFullyConfigured
  }

  var body: some View {
    Group {
      if shouldShow {
        BackgroundRunNoticeCard {
          withAnimation(.easeInOut(duration: 0.2)) {
            hasAcknowledgedBackgroundRunNotice = true
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}

private struct BackgroundRunNoticeCard: View {
  let onAcknowledge: () -> Void

  var body: some View {
    SectionBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(Color.green)
          Text("You're all set")
            .font(.headline)
        }

        Text("L'Alfred is now configured. While it's running, it stays in the background — no Dock icon, no foreground window.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Text("To open this window again, click the L'Alfred icon in the menu bar (top‑right of your screen) and choose **Settings**.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          Spacer()
          Button("Got it", action: onAcknowledge)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
  }
}

#Preview("Background Run Notice") {
  BackgroundRunNoticeCard(onAcknowledge: {})
    .padding()
    .frame(width: 480)
}
