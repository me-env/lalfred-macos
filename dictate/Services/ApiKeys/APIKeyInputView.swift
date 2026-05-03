import SwiftUI

struct APIKeyInputView: View {
  private static let apiKeyStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyElevenLabs)

  @State private var apiKey: String

  var onSubmit: (String) -> Void = { _ in }

  init(onSubmit: @escaping (String) -> Void = { _ in }) {
    self.onSubmit = onSubmit
    _apiKey = State(initialValue: Self.apiKeyStore.load() ?? "")
  }

  private func saveToDefaults() {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      Self.apiKeyStore.remove()
    } else {
      Self.apiKeyStore.save(trimmed)
    }
    onSubmit(trimmed)
  }

  var body: some View {
    SectionBoxWithTitle("11L API Key", caption: "Stored in app defaults on this Mac.") {
      SecureField("Enter your API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .onChange(of: apiKey) {
          saveToDefaults()
        }
    }
  }
}

#Preview {
  APIKeyInputView()
    .padding()
}
