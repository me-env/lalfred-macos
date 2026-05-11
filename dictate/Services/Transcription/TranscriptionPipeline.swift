import Foundation


func runTransformationPipeline(at fileURL: URL) async throws -> String {
  let audioTranscriber: STTProvider = makeDefaultAudioTranscriber()
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let transcript = try await audioTranscriber.transcribeAudio(
    at: fileURL,
    additionalVocabulary: keyTermsStore.load()
  )

  return snippetProcessor.process(transcript: transcript)
}

private func makeDefaultAudioTranscriber() -> STTProvider {
  let apiKeyStore = APIKeyStore(key: AppDefaultsKey.apiKeyElevenLabs)
  let isSubscribed = UserDefaults.standard.bool(forKey: AppDefaultsKey.accountIsSubscribed)
  let mode: TransportMode = isSubscribed && hasValue(apiKeyStore.load()) ? .direct : .proxy
  
  return ScribeClient(apiKeyStore: apiKeyStore, mode: mode)
}

private func hasValue(_ value: String?) -> Bool {
  guard let value else {
    return false
  }
  return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
