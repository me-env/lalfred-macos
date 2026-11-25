import Foundation


/// Joins segment transcripts into one text.
nonisolated enum TranscriptJoiner {
  /// Trims each text, drops empty ones, and separates them with a space, except between two
  /// characters of scripts written without spaces.
  static func join(_ texts: [String]) -> String {
    texts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .reduce("") { joined, text in
        guard let last = joined.unicodeScalars.last, let first = text.unicodeScalars.first else { return joined + text }
        let separator = isWrittenWithoutSpaces(last) && isWrittenWithoutSpaces(first) ? "" : " "
        return joined + separator + text
      }
  }

  /// Chinese, Japanese and Thai characters, and CJK punctuation.
  private static func isWrittenWithoutSpaces(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0E00...0x0E7F, // Thai
         0x3000...0x30FF, // CJK punctuation, Hiragana, Katakana
         0x3400...0x4DBF, // CJK Extension A
         0x4E00...0x9FFF, // CJK Unified Ideographs
         0xF900...0xFAFF, // CJK Compatibility Ideographs
         0xFF00...0xFFEF: // Fullwidth forms
      return true
    default:
      return false
    }
  }
}
