import Foundation


func runTransformationPipeline(audio: AsyncThrowingStream<Data, Error>) async throws -> String {
  let settings = TranscriptionSettings.load()
  let audioTranscriber: STTProvider = makeAudioTranscriber(settings: settings)
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let keyterms = Array(keyTermsStore.keyTermsForRequest()
    .filter { settings.provider.ignoredKeytermReason($0) == nil }
    .suffix(settings.provider.maxKeyterms))

  let segmentedTranscriber = SegmentedTranscriber(
    transcribeSegment: { @MainActor segment in
      try await audioTranscriber.transcribeAudio(segment, keyterms: keyterms)
    },
    makeDetector: { try? SoundAnalysisVoiceActivityDetector() },
    properNouns: capitalizedWords(of: keyTermsStore.load())
  )
  let transcript = try await segmentedTranscriber.transcribe(audio)

  return snippetProcessor.process(transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
}

func runTransformationPipeline(recordedAudio: Data) async throws -> String {
  let audio = AsyncThrowingStream<Data, Error> { continuation in
    continuation.yield(recordedAudio)
    continuation.finish()
  }
  return try await runTransformationPipeline(audio: audio)
}

/// The capitalized words of the user's dictionary terms: "Claude" and "Code" in "Claude Code".
private func capitalizedWords(of terms: [String]) -> Set<String> {
  Set(terms.flatMap { $0.split(whereSeparator: \.isWhitespace) }.filter { $0.first?.isUppercase == true }.map(String.init))
}

private func makeAudioTranscriber(settings: TranscriptionSettings) -> STTProvider {
  switch settings.provider {
  case .scribeV2:
    return ScribeClient(languageCode: settings.languageCode, transcriptEdit: settings.transcriptEdit)
  case .voxtral:
    return VoxtralClient(languageCode: settings.languageCode)
  }
}
