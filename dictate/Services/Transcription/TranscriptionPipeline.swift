import Foundation

private let defaultLLMInstruction = """
Reformat the user's message. Fix grammar, spelling, and punctuation. Remove filler words like "um" and "uh". Break long content into paragraphs. Keep the original tone and meaning. Only output the cleaned text, nothing else.
"""

func runLLMTransform(transcript: String, llmInstruction: String) async throws -> String {
  if llmInstruction.isEmpty || transcript.isEmpty {
    return transcript
  }

  let llmPostProcessor: LLMProvider = makeDefaultLLMPostProcessor()

  return try await llmPostProcessor.process(
    userPrompt: transcript,
    instruction: llmInstruction
  )
}

func runTransformationPipeline(at fileURL: URL) async throws -> String {
  let audioTranscriber: STTProvider = makeDefaultAudioTranscriber()
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let transcript = try await audioTranscriber.transcribeAudio(
    at: fileURL,
    additionalVocabulary: keyTermsStore.load()
  )

  print("LLM Instructions \(defaultLLMInstruction)")
  print("User prompt \(transcript)")

  let llmAdjustedTranscript: String = try await runLLMTransform(
    transcript: transcript,
    llmInstruction: defaultLLMInstruction
  )
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
