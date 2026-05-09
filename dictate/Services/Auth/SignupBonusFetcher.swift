import Foundation
import OSLog

/// Fetches the public signup-bonus credit amount from the API and caches it
/// in UserDefaults so the logged-out card can show the up-to-date value
/// without flicker on subsequent launches.
///
/// The endpoint is public (no auth header required) and the value is owned
/// by the API config — changing `initial_free_credits` server-side updates
/// the landing page and this app on the next fetch.
@MainActor
enum SignupBonusFetcher {
  private static let logger = Logger(subsystem: "fr.lalfred.dictate", category: "SignupBonus")

  static func refresh(
    userDefaults: UserDefaults = .standard,
    urlSession: URLSession = .shared
  ) async {
    do {
      var request = URLRequest(url: APIEndpoints.signupBonus)
      request.httpMethod = "GET"
      request.setValue("application/json", forHTTPHeaderField: "Accept")

      let (data, response) = try await urlSession.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode) else {
        logger.error("Signup bonus fetch failed with non-2xx status")
        return
      }

      let decoded = try JSONDecoder().decode(SignupBonusResponse.self, from: data)
      guard decoded.credits >= 0 else {
        logger.error("Signup bonus payload had negative credits, ignoring")
        return
      }

      userDefaults.set(decoded.credits, forKey: AppDefaultsKey.signupBonusCredits)
      logger.info("Signup bonus updated to \(decoded.credits, privacy: .public) credits")
    } catch {
      logger.error("Signup bonus fetch failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}

private struct SignupBonusResponse: Decodable {
  let credits: Int
}
