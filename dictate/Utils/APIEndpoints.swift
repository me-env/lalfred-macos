import Foundation

/// API environments the app can target. Add a new case here if a new backend
/// environment is introduced.
enum APIEnvironment: String, CaseIterable, Identifiable {
  case production
  case staging

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .production: return "Production"
    case .staging:    return "Staging"
    }
  }

  var baseURL: URL {
    switch self {
    case .production: return URL(string: "https://api.dictate.lalfred.ai")!
    case .staging:    return URL(string: "https://api.staging.dictate.lalfred.ai")!
    }
  }
}

/// Reads/writes the currently selected `APIEnvironment` from UserDefaults.
/// Falls back to `.production` whenever nothing is stored or the stored value
/// is unrecognized.
enum APIEnvironmentStore {
  static var current: APIEnvironment {
    get {
      let raw = UserDefaults.standard.string(forKey: AppDefaultsKey.apiEnvironment) ?? ""
      return APIEnvironment(rawValue: raw) ?? .production
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: AppDefaultsKey.apiEnvironment)
    }
  }
}

/// Whitelist of developer email addresses that are allowed to toggle the API
/// environment from within the app. Add additional teammates here.
enum DeveloperEmails {
  static let allowed: [String] = [
    "cyprien.r25@gmail.com",
  ]

  static func contains(_ email: String) -> Bool {
    let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    return allowed.contains { $0.lowercased() == normalized }
  }
}

enum APIEndpoints {
  static var baseURL: URL { APIEnvironmentStore.current.baseURL }

  static var googleLogin: URL    { baseURL.appending(path: "auth/google/login") }
  static var accountProfile: URL { baseURL.appending(path: "users/me") }
  static var transcribe: URL     { baseURL.appending(path: "transcribe") }
  static var claimsRedeem: URL   { baseURL.appending(path: "claims/redeem") }
  static var llmChat: URL        { baseURL.appending(path: "llm/chat") }
  static var signupBonus: URL    { baseURL.appending(path: "credits/signup-bonus") }
}
