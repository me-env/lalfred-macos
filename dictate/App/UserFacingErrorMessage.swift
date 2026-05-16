import Foundation


enum UserFacingErrorMessage {
  static func format(_ error: Error) -> String {
    if let urlError = error as? URLError {
      return networkMessage(for: urlError)
    }

    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
      return description
    }

    let fallback = error.localizedDescription
    if !fallback.isEmpty {
      return fallback
    }

    return "Something went wrong"
  }

  private static func networkMessage(for error: URLError) -> String {
    switch error.code {
    case .notConnectedToInternet:
      return "No internet connection"
    case .networkConnectionLost:
      return "Network connection lost"
    case .timedOut:
      return "Request timed out, check your connection"
    case .cannotFindHost,
         .dnsLookupFailed,
         .cannotConnectToHost:
      return "Can't reach Lalfred server"
    case .secureConnectionFailed,
         .serverCertificateUntrusted,
         .serverCertificateHasBadDate,
         .serverCertificateNotYetValid,
         .serverCertificateHasUnknownRoot:
      return "Secure connection failed"
    case .internationalRoamingOff, .dataNotAllowed:
      return "Network unavailable"
    default:
      return "Network error: \(error.localizedDescription)"
    }
  }
}
