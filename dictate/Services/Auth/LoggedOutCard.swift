import SwiftUI

struct LoggedOutCard: View {
  let model: AccountTabViewModel

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
}
