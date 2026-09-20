import SwiftUI

struct LoggedOutCard: View {
  let model: AccountTabViewModel

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Sign in to your account")
          .font(.title3.weight(.semibold))

        Text(introMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Button(model.isLoadingAuthURL ? "Opening Google..." : "Continue with Google") {
          Task {
            await model.startGoogleOAuth()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoadingAuthURL)

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

  private var introMessage: String {
    "Sign in to use L'Alfred with your own ElevenLabs API key."
  }
}
