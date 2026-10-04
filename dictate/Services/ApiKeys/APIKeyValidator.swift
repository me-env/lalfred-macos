import Foundation


enum APIKeyValidation {
  case valid
  case invalid
  /// The check itself failed (offline, server error), so nothing is known about the key.
  case unknown
}

enum APIKeyValidationState {
  case idle
  case checking
  case done(APIKeyValidation)
}

/// Checks a key with a cheap authenticated request before it's used for a transcription.
enum APIKeyValidator {
  /// Checks the key saved for `provider`; nil when none is saved.
  static func validateSavedKey(for provider: APIKeyProvider) async -> APIKeyValidation? {
    let keychainKey = provider.key
    // Keychain reads can block, so they stay off the main thread.
    guard let apiKey = await Task.detached(operation: { Keychain().get(keychainKey) }).value else {
      return nil
    }
    return await validate(apiKey, for: provider)
  }

  static func validate(_ apiKey: String, for provider: APIKeyProvider, session: URLSession = .shared) async -> APIKeyValidation {
    var request = URLRequest(url: endpoint(for: provider), timeoutInterval: 10)
    switch provider {
    case .elevenLabs:
      request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    case .mistral:
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    guard let (data, response) = try? await session.data(for: request),
          let statusCode = (response as? HTTPURLResponse)?.statusCode else {
      return .unknown
    }

    switch statusCode {
    case 200..<300:
      return .valid
    case 401, 403:
      // A key restricted to speech to text can't read the user, but ElevenLabs still recognized it.
      let isRestrictedKey = String(decoding: data, as: UTF8.self).contains("missing_permissions")
      return isRestrictedKey ? .valid : .invalid
    default:
      return .unknown
    }
  }

  private static func endpoint(for provider: APIKeyProvider) -> URL {
    switch provider {
    case .elevenLabs:
      return URL(string: "https://api.elevenlabs.io/v1/user")!
    case .mistral:
      return URL(string: "https://api.mistral.ai/v1/models")!
    }
  }
}
