import Foundation
import OSLog

private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "AuthManager")


extension Notification.Name {
  /// Posted on the main thread whenever the auth token is set or cleared.
  /// Subscribers (e.g. ``AppConfigurationModel``) use this to refresh their
  /// view of `isSignedIn` without having to poll `UserDefaults`.
  static let appAuthStateDidChange = Notification.Name("fr.lalfred.dictate.AuthStateDidChange")
}


@MainActor
final class AuthManager {
  static let shared = AuthManager()
  
  private static let maxRefreshAttempts = 3
  
  enum AuthError: LocalizedError {
    case invalidResponse
    case missingAuthorizationURL
    case missingAuthToken
    case profileRequestFailed(statusCode: Int, message: String)
    case temporarilyUnavailable(String)
    
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
      case let .temporarilyUnavailable(message):
        return message
      }
    }
    
    var isTransient: Bool {
      if case .temporarilyUnavailable = self {
        return true
      }
      return false
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
    NotificationCenter.default.post(name: .appAuthStateDidChange, object: nil)
    
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
  
  func signOut() {
    tokenStore.remove()
    
    for key in AppDefaultsKey.accountScoped {
      userDefaults.removeObject(forKey: key)
    }
    
    logger.info("Signed out: cleared the auth token and account-scoped values only")
    NotificationCenter.default.post(name: .appAuthStateDidChange, object: nil)
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
    
    var attempt = 0
    while true {
      attempt += 1
      
      do {
        persist(try await requestAccountProfile())
        return
      } catch let error as AuthError where error.isTransient && attempt < Self.maxRefreshAttempts {
        let delay = pow(3.0, Double(attempt - 1))
        logger.info("Account refresh attempt \(attempt) failed; retrying in \(delay, format: .fixed(precision: 0))s")
        try await Task.sleep(for: .seconds(delay))
      }
    }
  }
  
  private func requestAccountProfile() async throws -> AccountDetails {
    var request = URLRequest(url: accountProfileEndpoint())
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    applyAuthorizationHeader(to: &request)
    
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch let error as URLError {
      throw AuthError.temporarilyUnavailable(error.localizedDescription)
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200..<300:
      break
    case 408, 429, 500...599:
      throw AuthError.temporarilyUnavailable(
        "The server is unavailable (\(httpResponse.statusCode)): \(parseServerMessage(from: data) ?? "Unknown server error")"
      )
    default:
      throw AuthError.profileRequestFailed(
        statusCode: httpResponse.statusCode,
        message: parseServerMessage(from: data) ?? "Unknown server error"
      )
    }
    
    return try JSONDecoder().decode(AccountProfileResponse.self, from: data).resolvedAccountDetails
  }
  
  private func persist(_ details: AccountDetails) {
    if let email = details.email {
      userDefaults.set(email, forKey: AppDefaultsKey.accountEmail)
    }
    if let firstName = details.firstName {
      userDefaults.set(firstName, forKey: AppDefaultsKey.accountFirstName)
    }
    if let lastName = details.lastName {
      userDefaults.set(lastName, forKey: AppDefaultsKey.accountLastName)
    }
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
  let email: String?
  let firstName: String?
  let lastName: String?
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
  
  var resolvedAccountDetails: AccountDetails {
    let trimmedFullName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    
    var fallbackFirstName: String?
    var fallbackLastName: String?
    if !trimmedFullName.isEmpty {
      let parts = trimmedFullName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
      fallbackFirstName = parts.first.map(String.init)
      fallbackLastName = parts.count > 1 ? String(parts[1]) : nil
    }
    
    return AccountDetails(
      email: Self.nonEmpty(email),
      firstName: Self.nonEmpty(firstName ?? first_name ?? givenName ?? given_name) ?? fallbackFirstName,
      lastName: Self.nonEmpty(lastName ?? last_name ?? familyName ?? family_name) ?? fallbackLastName
    )
  }
  
  private static func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}
