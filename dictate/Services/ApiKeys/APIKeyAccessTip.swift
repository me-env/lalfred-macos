
enum APIKeyAccessTip {
  case signedOut
  case notSubscribed

  var message: String {
    switch self {
    case .signedOut:
      return "Sign in and subscribe to add your own API key."
    case .notSubscribed:
      return "Your own API key is available with an active subscription."
    }
  }
}
