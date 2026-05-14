import Foundation
import OSLog

private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "AuthManager")


@MainActor
final class AuthManager {
  static let shared = AuthManager()
  
  enum AuthError: LocalizedError {
    case invalidResponse
    case missingAuthorizationURL
    case missingAuthToken
    case profileRequestFailed(statusCode: Int, message: String)
    
    var errorDescription: String? {
      switch self {
      case .invalidResponse:
        return "Unexpected OAuth response from server."
      case .missingAuthorizationURL:
        return "Server did not provide a Google authorization URL."
      case .missingAuthToken:
        return "You must be signed in to load account details."
      case let .profileRequestFailed(statusCode, message):
        return "Failed to load account details (\(statusCode)): \(message)"
      }
    }
  }
  
  private let tokenStore: KeychainStore
  private let userDefaults: UserDefaults
  private let urlSession: URLSession
  
  private init(
    userDefaults: UserDefaults = .standard,
    urlSession: URLSession = .shared
  ) {
    self.userDefaults = userDefaults
    self.urlSession = urlSession
    self.tokenStore = KeychainStore(
      key: AppDefaultsKey.authToken
    )
  }
  
  func fetchGoogleAuthorizationURL() async throws -> URL {
    let loginEndpoint = googleLoginEndpoint()
    
    let (data, response) = try await urlSession.data(from: loginEndpoint)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw AuthError.invalidResponse
    }
    
    if let authURL = parseAuthorizationURL(from: data) {
      return authURL
    }
    
    if let finalURL = httpResponse.url,
       finalURL != loginEndpoint {
      return finalURL
    }
    
    throw AuthError.missingAuthorizationURL
  }
  
  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    logger.info("handleIncomingURL \(url)")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryKeys = components?.queryItems?.map(\.name) ?? []
    
    guard url.scheme?.lowercased() == "lalfred",
          url.host?.lowercased() == "auth",
          url.path == "/callback"
    else {
      logger.error("Rejected callback URL due to scheme/host/path mismatch: \(url.absoluteString, privacy: .public)")
      return false
    }
    
    guard let token = components?.queryItems?.first(where: { $0.name == "token" })?.value else {
      logger.error("Callback URL missing token query item. Keys present: \(queryKeys.joined(separator: ","), privacy: .public)")
      return false
    }
    
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    logger.info("Received callback token with length \(trimmedToken.count, privacy: .public)")
    setToken(trimmedToken)
    return true
  }
  
  func setToken(_ token: String) {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedToken.isEmpty else {
      logger.error("Refusing to save empty auth token")
      return
    }
    
    tokenStore.save(trimmedToken)
    userDefaults.set(true, forKey: AppDefaultsKey.isSignedIn)
    logger.info("Saved auth token and marked user as signed in")
    
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.refreshAccountDetails()
        logger.info("Loaded account details after sign-in")
      } catch {
        logger.error("Failed loading account details after sign-in: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  func clearToken() {
    tokenStore.remove()
    userDefaults.set(false, forKey: AppDefaultsKey.isSignedIn)
  }
  
  func signOutAndResetPreferences() {
    clearToken()
    
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      userDefaults.removePersistentDomain(forName: bundleIdentifier)
      logger.info("Cleared persisted preferences for bundle: \(bundleIdentifier, privacy: .public)")
    } else {
      logger.error("Unable to clear preferences: missing bundle identifier")
    }
    
    userDefaults.set(false, forKey: AppDefaultsKey.isSignedIn)
    logger.info("Completed sign out and local preference cleanup")
  }
  
  func authToken() -> String? {
    guard let token = tokenStore.load() else {
      return nil
    }
    
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedToken.isEmpty ? nil : trimmedToken
  }
  
  func applyAuthorizationHeader(to request: inout URLRequest) {
    guard let token = authToken() else {
      return
    }
    
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  
  func refreshAccountDetails() async throws {
    guard authToken() != nil else {
      throw AuthError.missingAuthToken
    }
    
    let profileEndpoint = accountProfileEndpoint()
    
    var request = URLRequest(url: profileEndpoint)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    applyAuthorizationHeader(to: &request)
    
    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw AuthError.profileRequestFailed(statusCode: httpResponse.statusCode, message: message)
    }
    
    let decoded = try JSONDecoder().decode(AccountProfileResponse.self, from: data)
    let details = decoded.resolvedAccountDetails
    
    userDefaults.set(details.email, forKey: AppDefaultsKey.accountEmail)
    userDefaults.set(details.firstName, forKey: AppDefaultsKey.accountFirstName)
    userDefaults.set(details.lastName, forKey: AppDefaultsKey.accountLastName)
    userDefaults.set(details.credits, forKey: AppDefaultsKey.accountCredits)
    userDefaults.set(details.isSubscribed, forKey: AppDefaultsKey.accountIsSubscribed)
  }
  
  private func parseAuthorizationURL(from data: Data) -> URL? {
    if let decoded = try? JSONDecoder().decode(OAuthLoginResponse.self, from: data),
       let rawURL = decoded.authorizationURL ?? decoded.authorizationUrl ?? decoded.url {
      return URL(string: rawURL)
    }
    
    if let rawURL = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) {
      return URL(string: rawURL)
    }
    
    return nil
  }
  
  private func parseServerMessage(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
      return response.detail
    }
    
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private func googleLoginEndpoint() -> URL {
    APIEndpoints.googleLogin
  }
  
  private func accountProfileEndpoint() -> URL {
    APIEndpoints.accountProfile
  }
}

private struct OAuthLoginResponse: Decodable {
  let url: String?
  let authorizationURL: String?
  let authorizationUrl: String?
}

private struct AccountDetails {
  let email: String
  let firstName: String
  let lastName: String
  let credits: Int
  let isSubscribed: Bool
}

private struct AccountProfileResponse: Decodable {
  let email: String?
  let name: String?
  let firstName: String?
  let first_name: String?
  let givenName: String?
  let given_name: String?
  let lastName: String?
  let last_name: String?
  let familyName: String?
  let family_name: String?
  let credits: Int?
  let creditBalance: Int?
  let credit_balance: Int?
  let isSubscribed: Bool?
  let is_subscribed: Bool?
  let subscriptionStatus: String?
  let subscription_status: String?
  
  var resolvedAccountDetails: AccountDetails {
    let trimmedFullName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    
    let fallbackFirstName: String
    let fallbackLastName: String
    if trimmedFullName.isEmpty {
      fallbackFirstName = ""
      fallbackLastName = ""
    } else {
      let parts = trimmedFullName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
      fallbackFirstName = parts.first.map(String.init) ?? ""
      fallbackLastName = parts.count > 1 ? String(parts[1]) : ""
    }
    
    let resolvedFirstName = firstName ?? first_name ?? givenName ?? given_name ?? fallbackFirstName
    let resolvedLastName = lastName ?? last_name ?? familyName ?? family_name ?? fallbackLastName
    let resolvedCredits = credits ?? creditBalance ?? credit_balance ?? 0
    
    let resolvedIsSubscribed: Bool
    if let explicit = isSubscribed ?? is_subscribed {
      resolvedIsSubscribed = explicit
    } else if let status = subscriptionStatus ?? subscription_status {
      resolvedIsSubscribed = status.lowercased() == "active"
    } else {
      resolvedIsSubscribed = false
    }
    
    return AccountDetails(
      email: email ?? "",
      firstName: resolvedFirstName,
      lastName: resolvedLastName,
      credits: resolvedCredits,
      isSubscribed: resolvedIsSubscribed
    )
  }
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}
