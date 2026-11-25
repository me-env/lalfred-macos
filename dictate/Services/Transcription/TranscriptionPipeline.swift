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
    properNouns: keyTermsStore.capitalizedWords()
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

private func makeAudioTranscriber(settings: TranscriptionSettings) -> STTProvider {
  switch settings.provider {
  case .scribeV2:
    return ScribeClient(languageCode: settings.languageCode, transcriptEdit: settings.transcriptEdit)
  case .voxtral:
    return VoxtralClient(languageCode: settings.languageCode)
  }
}
