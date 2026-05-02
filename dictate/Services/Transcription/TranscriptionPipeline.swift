import Foundation


struct TranscriptionPipeline: TranscribingPipeline {
  private let audioTranscriber: STTProvider
  private let llmPostProcessor: LLMProvider
  private let snippetProcessor: SnippetTranscriptProcessor

  init(
    audioTranscriber: STTProvider = ScribeClient(),
    llmPostProcessor: LLMProvider = OpenAITranscriptPostProcessor(),
    snippetProcessor: SnippetTranscriptProcessor = SnippetTranscriptProcessor()
  ) {
    self.audioTranscriber = audioTranscriber
    self.llmPostProcessor = llmPostProcessor
    self.snippetProcessor = snippetProcessor
  }

  func runTransformationPipeline(at fileURL: URL, context: ModeTranscriptionContext) async throws -> String {
    let transcript = try await audioTranscriber.transcribeAudio(
      at: fileURL,
      additionalVocabulary: context.additionalVocabulary
    )

    let llmInstruction = context.llmInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let llmAdjustedTranscript: String
    if llmInstruction.isEmpty {
      llmAdjustedTranscript = transcript
    } else {
      llmAdjustedTranscript = try await llmPostProcessor.process(transcript: transcript, context: context)
    }

    return snippetProcessor.process(transcript: llmAdjustedTranscript)
  }
}
