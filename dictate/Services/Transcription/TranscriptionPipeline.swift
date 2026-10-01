import Foundation


func runTransformationPipeline(audio: AsyncThrowingStream<Data, Error>) async throws -> String {
  let audioTranscriber: STTProvider = makeDefaultAudioTranscriber()
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let transcript = try await audioTranscriber.transcribeAudio(
    audio,
    keyterms: keyTermsStore.keyTermsForRequest()
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

private func makeDefaultAudioTranscriber() -> STTProvider {
  let settings = TranscriptionSettings.load()

  switch settings.provider {
  case .scribeV2:
    return ScribeClient(languageCode: settings.languageCode, transcriptEdit: settings.transcriptEdit)
  case .scribeV2Realtime:
    return ScribeRealtimeClient(options: .init(
      languageCode: settings.languageCode,
      secondaryLanguages: settings.realtimeSecondaryLanguages,
      transcriptEdit: settings.transcriptEdit
    ))
  }
}
