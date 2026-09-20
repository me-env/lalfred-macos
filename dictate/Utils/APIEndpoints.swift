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

let developerEmails: Set<String> = [
  "cyprien.r25@gmail.com",
]

enum APIEndpoints {
  static var baseURL: URL { APIEnvironmentStore.current.baseURL }

  static var googleLogin: URL    { baseURL.appending(path: "auth/google/login") }
  static var accountProfile: URL { baseURL.appending(path: "users/me") }
}
