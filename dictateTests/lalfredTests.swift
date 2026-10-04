import Foundation
import Testing
@testable import L_Alfred


struct lalfredTests {
  @Test func serverErrorMessageReadsEveryProviderShape() {
    #expect(ServerErrorMessage.parse(Data(#"{"detail":"Bad key"}"#.utf8)) == "Bad key")
    #expect(ServerErrorMessage.parse(Data(#"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#.utf8)) == "Invalid API key")
    #expect(ServerErrorMessage.parse(Data(#"{"message":"Context bias item 'A: U:' is invalid"}"#.utf8)) == "Context bias item 'A: U:' is invalid")
    #expect(ServerErrorMessage.parse(Data(#"{"detail":[{"msg":"field required"}]}"#.utf8)) == "field required")
    #expect(ServerErrorMessage.parse(Data("Bad Gateway".utf8)) == "Bad Gateway")
    #expect(ServerErrorMessage.parse(Data()) == nil)
  }

  @Test func transcriptionErrorWordingAndRetry() {
    let unauthorized = TranscriptionError.requestFailed(.mistral, statusCode: 401, message: nil)
    #expect(unauthorized.errorDescription == "Invalid Mistral AI API key")
    #expect(!unauthorized.isTransient)
    #expect(TranscriptionError.requestFailed(.elevenLabs, statusCode: 429, message: nil).isTransient)
    #expect(TranscriptionError.requestFailed(.elevenLabs, statusCode: 503, message: nil).isTransient)
    #expect(TranscriptionError.missingAPIKey(.mistral).errorDescription == "Missing Mistral AI API key")
  }

  @Test func multipartFormDataLayout() {
    var form = MultipartFormData()
    form.appendField("model", value: "voxtral")
    form.appendFileHeader(name: "file", filename: "audio.wav", contentType: "audio/wav")
    let body = String(decoding: form.head + Data("WAV".utf8) + form.tail, as: UTF8.self)
    let b = form.boundary
    #expect(body == "--\(b)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvoxtral\r\n"
      + "--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
      + "WAV\r\n--\(b)--\r\n")
  }

  @Test func voxtralIgnoresKeytermsWithWhitespaceOrCommas() {
    #expect(TranscriptionProvider.voxtral.ignoredKeytermReason("Kubernetes") == nil)
    #expect(TranscriptionProvider.voxtral.ignoredKeytermReason("A: U:") != nil)
    #expect(TranscriptionProvider.voxtral.ignoredKeytermReason("foo,bar") != nil)
    #expect(TranscriptionProvider.scribeV2.ignoredKeytermReason("A: U:") == nil)
    #expect(TranscriptionProvider.voxtralRealtime.ignoredKeytermReason("Kubernetes") != nil)
  }

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
