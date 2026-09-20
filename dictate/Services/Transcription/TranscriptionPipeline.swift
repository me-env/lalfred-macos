import Foundation


func runTransformationPipeline(at fileURL: URL) async throws -> String {
  let audioTranscriber: STTProvider = makeDefaultAudioTranscriber()
  let snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  let keyTermsStore = KeyTermsStore()

  let transcript = try await audioTranscriber.transcribeAudio(
    at: fileURL,
    keyterms: keyTermsStore.keyTermsForRequest()
  )

  return snippetProcessor.process(transcript: transcript)
}

private func makeDefaultAudioTranscriber() -> STTProvider {
  ScribeClient()
}
