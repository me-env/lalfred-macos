import Foundation

enum APIEndpoints {
  static let baseURL: URL = {
    guard let string = Bundle.main.object(forInfoDictionaryKey: "LalfredAPIBaseURL") as? String,
          let url = URL(string: string) else {
      fatalError("LalfredAPIBaseURL is missing or invalid in Info.plist")
    }
    return url
  }()

  static let googleLogin     = baseURL.appending(path: "auth/google/login")
  static let accountProfile  = baseURL.appending(path: "users/me")
  static let transcribe      = baseURL.appending(path: "transcribe")
  static let claimsRedeem    = baseURL.appending(path: "claims/redeem")
  static let llmChat         = baseURL.appending(path: "llm/chat")
  static let signupBonus     = baseURL.appending(path: "credits/signup-bonus")
}
