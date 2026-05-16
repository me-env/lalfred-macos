import Foundation
import Testing
@testable import L_Alfred


struct UserFacingErrorMessageTests {
  @Test func notConnectedToInternetReturnsFriendlyMessage() {
    let error = URLError(.notConnectedToInternet)
    #expect(UserFacingErrorMessage.format(error) == "No internet connection")
  }

  @Test func timedOutReturnsFriendlyMessage() {
    let error = URLError(.timedOut)
    #expect(UserFacingErrorMessage.format(error) == "Request timed out, check your connection")
  }

  @Test func networkConnectionLostReturnsFriendlyMessage() {
    let error = URLError(.networkConnectionLost)
    #expect(UserFacingErrorMessage.format(error) == "Network connection lost")
  }

  @Test func cannotFindHostReturnsServerUnreachableMessage() {
    let error = URLError(.cannotFindHost)
    #expect(UserFacingErrorMessage.format(error) == "Can't reach Lalfred server")
  }

  @Test func dnsLookupFailedReturnsServerUnreachableMessage() {
    let error = URLError(.dnsLookupFailed)
    #expect(UserFacingErrorMessage.format(error) == "Can't reach Lalfred server")
  }

  @Test func cannotConnectToHostReturnsServerUnreachableMessage() {
    let error = URLError(.cannotConnectToHost)
    #expect(UserFacingErrorMessage.format(error) == "Can't reach Lalfred server")
  }

  @Test func secureConnectionFailedReturnsTLSMessage() {
    let error = URLError(.secureConnectionFailed)
    #expect(UserFacingErrorMessage.format(error) == "Secure connection failed")
  }

  @Test func unknownURLErrorPrependsNetworkErrorPrefix() {
    let error = URLError(.unknown)
    let message = UserFacingErrorMessage.format(error)
    #expect(message.hasPrefix("Network error: "))
  }

  @Test func localizedErrorDescriptionIsPreferredForNonURLErrors() {
    struct CustomError: LocalizedError {
      var errorDescription: String? { "Custom failure description" }
    }
    #expect(UserFacingErrorMessage.format(CustomError()) == "Custom failure description")
  }

  @Test func localizedErrorWithEmptyDescriptionFallsBackToDefault() {
    struct EmptyError: LocalizedError {
      var errorDescription: String? { "" }
    }
    let message = UserFacingErrorMessage.format(EmptyError())
    #expect(!message.isEmpty)
  }

  @Test func nsErrorWithoutLocalizedErrorUsesLocalizedDescriptionFallback() {
    let error = NSError(
      domain: "TestDomain",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "Plain NSError message"]
    )
    #expect(UserFacingErrorMessage.format(error) == "Plain NSError message")
  }
}
