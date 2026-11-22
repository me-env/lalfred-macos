import Foundation

nonisolated enum RecordedAudio {
  /// True when 16-bit PCM `audio` holds only exact zeros: the microphone delivered no sound at all,
  /// which transcription models turn into invented text.
  static func isDigitallySilent(_ audio: Data) -> Bool {
    audio.allSatisfy { $0 == 0 }
  }
}
