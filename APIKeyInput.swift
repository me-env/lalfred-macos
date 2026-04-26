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
    VStack(alignment: .leading, spacing: 8) {
      Text("11L API Key")
        .font(.headline)
      
      SecureField("Enter your API key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          persistAPIKey()
        }
      
      Text("Stored securely in your macOS Keychain.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      .quaternary.opacity(0.2),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
  }
}

#Preview {
  APIKeyInput()
    .padding()
}
