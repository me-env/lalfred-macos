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
  
  private func persistAPIKey() {
    print("Save API key")
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if trimmedKey.isEmpty {
      Self.apiKeyStore.remove()
    } else {
      Self.apiKeyStore.save(trimmedKey)
      apiKey = trimmedKey
    }
    print("API key saved")
    
    onSubmit(trimmedKey)
  }
  
  var body: some View {
    SectionBox("11L API Key", caption: "Stored securely in your macOS Keychain.") {
      SecureField("Enter your API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          persistAPIKey()
        }
    }
  }
}

#Preview {
  APIKeyInput()
    .padding()
}
