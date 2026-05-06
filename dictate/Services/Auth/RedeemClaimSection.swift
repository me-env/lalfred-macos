import SwiftUI

/// Section in the Account tab where signed-in users redeem a purchase code
/// they received by email. Surfaces paste support, normalises the typed value
/// (auto-strips `-`), and forwards submission to the view model. The success
/// sheet is rendered by the parent so confetti covers the whole window.
struct RedeemClaimSection: View {
  @Bindable var model: RedeemClaimViewModel

  @FocusState private var isInputFocused: Bool

  var body: some View {
    SectionBoxWithTitle(
      "Redeem a code",
      caption: "Enter the code you received by email after purchasing credits or a subscription.",
    ) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          TextField("XXXX-XXXX-XXXX-XXXX", text: $model.inputKey)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .disableAutocorrection(true)
            .focused($isInputFocused)
            .onSubmit { submit() }

          Button {
            model.pasteFromClipboard()
            isInputFocused = true
          } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
          }
          .buttonStyle(.bordered)
          .help("Paste from clipboard (dashes are removed automatically)")

          Button {
            submit()
          } label: {
            if model.isSubmitting {
              ProgressView().controlSize(.small)
            } else {
              Text("Redeem")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!model.canSubmit)
          .keyboardShortcut(.defaultAction)
        }

        if !model.errorMessage.isEmpty {
          Text(model.errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
  }

  private func submit() {
    Task { await model.submit() }
  }
}

#Preview("Empty") {
  RedeemClaimSection(model: RedeemClaimViewModel())
    .padding()
    .frame(width: 520)
}
