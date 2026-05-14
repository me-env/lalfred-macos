import Foundation
import Testing
@testable import L_Alfred


struct lalfredTests {
  @Test func snippetWithPlainEmailKeyMatchesHyphenatedEmailTranscript() {
    let userDefaults = makeIsolatedUserDefaults()
    saveSnippets(
      [Snippet(key: "email", value: "EMAIL")],
      userDefaults: userDefaults
    )

    let result = SnippetTranscriptProcessor(userDefaults: userDefaults)
      .process(transcript: "send an e-mail now")

    #expect(result == "send an EMAIL now")
  }

  @Test func snippetWithHyphenatedEmailKeyMatchesPlainEmailTranscript() {
    let userDefaults = makeIsolatedUserDefaults()
    saveSnippets(
      [Snippet(key: "e-mail", value: "EMAIL")],
      userDefaults: userDefaults
    )

    let result = SnippetTranscriptProcessor(userDefaults: userDefaults)
      .process(transcript: "send an email now")
    
    #expect(result == "send an EMAIL now")
  }
  
  @Test func snippetFullMatchWithDot() {
    let userDefaults = makeIsolatedUserDefaults()
    saveSnippets(
      [Snippet(key: "e-mail", value: "EMAIL", fullMatch: true)],
      userDefaults: userDefaults
    )
    
    let result = SnippetTranscriptProcessor(userDefaults: userDefaults)
      .process(transcript: "Email.")
    
    #expect(result == "EMAIL")
  }

  private func makeIsolatedUserDefaults() -> UserDefaults {
    let suiteName = "lalfredTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }
  
  private func saveSnippets(_ snippets: [Snippet], userDefaults: UserDefaults) {
    UserDefaultsCodableStore<[Snippet]>(
      key: AppDefaultsKey.savedSnippets,
      userDefaults: userDefaults
    ).save(snippets)
  }
}
