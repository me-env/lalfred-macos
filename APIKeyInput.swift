//
//  APIKeyInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI

struct APIKeyInput: View {
  private static let apiKeyStore = APIKeyDefaultsStore(key: "apiKey.11l")

  @State private var apiKey: String

  var onSubmit: (String) -> Void = { _ in }

  init(onSubmit: @escaping (String) -> Void = { _ in }) {
    self.onSubmit = onSubmit
    _apiKey = State(initialValue: Self.apiKeyStore.load() ?? "")
  }

  private func saveToKeychain() {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      Self.apiKeyStore.remove()
    } else {
      Self.apiKeyStore.save(trimmed)
    }
    onSubmit(trimmed)
  }

  var body: some View {
    SectionBox("11L API Key", caption: "Stored securely in your macOS Keychain.") {
      SecureField("Enter your API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .onChange(of: apiKey) {
          saveToKeychain()
        }
    }
  }
}

#Preview {
  APIKeyInput()
    .padding()
}
