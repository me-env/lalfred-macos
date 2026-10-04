import Foundation


func runTransformationPipeline(audio: AsyncThrowingStream<Data, Error>) async throws -> String {
  let settings = TranscriptionSettings.load()
  let audioTranscriber: STTProvider = makeAudioTranscriber(settings: settings)
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let transcript = try await audioTranscriber.transcribeAudio(
    audio,
    keyterms: keyTermsStore.keyTermsForRequest()
      .filter { settings.provider.ignoredKeytermReason($0) == nil }
  )

  return snippetProcessor.process(transcript: transcript)
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
  case .scribeV2Realtime:
    return ScribeRealtimeClient(options: .init(
      languageCode: settings.languageCode,
      secondaryLanguages: settings.realtimeSecondaryLanguages,
      transcriptEdit: settings.transcriptEdit
    ))
  case .voxtral:
    return VoxtralClient(languageCode: settings.languageCode)
  case .voxtralRealtime:
    return VoxtralRealtimeClient()
  }
}
