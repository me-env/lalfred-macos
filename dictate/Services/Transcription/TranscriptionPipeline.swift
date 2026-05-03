import Foundation


func runTransformationPipeline(at fileURL: URL, mode: ModeDefinition) async throws -> String {
  let audioTranscriber: STTProvider = makeDefaultAudioTranscriber()
  let llmPostProcessor: LLMProvider = makeDefaultLLMPostProcessor()
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  
  let transcript = try await audioTranscriber.transcribeAudio(
    at: fileURL,
    additionalVocabulary: mode.additionalVocabulary
  )
  
  let llmInstruction = mode.llmInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  print("LLM Instructions \(llmInstruction)")
  print("User prompt \(transcript)")
  
  let llmAdjustedTranscript: String
  if llmInstruction.isEmpty {
    llmAdjustedTranscript = transcript
  } else {
    llmAdjustedTranscript = try await llmPostProcessor.process(
      userPrompt: transcript,
      instruction: llmInstruction
    )
  }
  
  return snippetProcessor.process(transcript: llmAdjustedTranscript)
}

private func makeDefaultAudioTranscriber() -> STTProvider {
  let apiKeyStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyElevenLabs)
  let isSubscribed = UserDefaults.standard.bool(forKey: AppDefaultsKey.accountIsSubscribed)
  print("isSubscribed=\(isSubscribed) hasApiKeyElevenLabs=\(hasValue(apiKeyStore.load()))")
  let mode: TransportMode = isSubscribed && hasValue(apiKeyStore.load()) ? .direct : .proxy
  return ScribeClient(apiKeyStore: apiKeyStore, mode: mode)
}

private func makeDefaultLLMPostProcessor() -> LLMProvider {
  let apiKeyStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyOpenAI)
  let isSubscribed = UserDefaults.standard.bool(forKey: AppDefaultsKey.accountIsSubscribed)
  print("isSubscribed=\(isSubscribed) hasApiKeyOpenAI=\(hasValue(apiKeyStore.load()))")
  let mode: TransportMode = isSubscribed && hasValue(apiKeyStore.load()) ? .direct : .proxy
  return OpenAITranscriptPostProcessor(apiKeyStore: apiKeyStore, mode: mode)
}

private func hasValue(_ value: String?) -> Bool {
  guard let value else {
    return false
  }
  return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
