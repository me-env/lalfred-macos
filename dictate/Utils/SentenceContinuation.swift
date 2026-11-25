import Foundation
import NaturalLanguage


/// Capitalization of text that continues a sentence instead of starting one.
nonisolated enum SentenceContinuation {
  /// Punctuation that ends a sentence, Latin and CJK.
  static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "．"]
  /// Closing quotes and brackets, which stand after the punctuation they close: `He said "Done."`.
  private static let closingCharacters: Set<Character> = ["\"", "”", "’", "'", ")", "]", "}", "»", "」", "』"]
  private static let apostrophes: Set<Character> = ["'", "’"]

  /// Whether `text` ends with sentence punctuation, possibly followed by closing quotes or brackets.
  static func endsSentence<S: StringProtocol>(_ text: S) -> Bool {
    guard let last = text.last(where: { !$0.isWhitespace && !closingCharacters.contains($0) }) else { return false }
    return sentenceTerminators.contains(last)
  }

  /// `text` with its first letter lowercased.
  static func lowercasingFirstLetter<S: StringProtocol>(of text: S) -> String {
    guard let first = text.first else { return String(text) }
    return first.lowercased() + text.dropFirst()
  }

  /// `text` lowercased at its start, unless its first word keeps its capital anywhere in a sentence:
  /// an all-caps word or acronym, "I" and its contractions, or a proper noun.
  static func continuingSentence(_ text: String, properNouns: Set<String> = []) -> String {
    let word = firstWord(of: text)
    guard word.first?.isUppercase == true,
          !isAllCaps(word),
          !isFirstPersonPronoun(word),
          !properNouns.contains(String(word)),
          !isTaggedAsName(firstWordOf: text) else { return text }
    return lowercasingFirstLetter(of: text)
  }

  /// The leading letters and apostrophes: "I'm" in "I'm here".
  static func firstWord(of text: String) -> Substring {
    text.prefix { $0.isLetter || apostrophes.contains($0) }
  }

  private static func isAllCaps(_ word: Substring) -> Bool {
    let letters = word.filter(\.isLetter)
    return letters.count > 1 && letters.allSatisfy(\.isUppercase)
  }

  /// "I", "I'm", "I'll", "I’d"...
  private static func isFirstPersonPronoun(_ word: Substring) -> Bool {
    word == "I" || (word.hasPrefix("I") && word.dropFirst().first.map(apostrophes.contains) == true)
  }

  /// A person, place or organization name per the on-device tagger.
  private static func isTaggedAsName(firstWordOf text: String) -> Bool {
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    let (tag, _) = tagger.tag(at: text.startIndex, unit: .word, scheme: .nameType)
    return tag == .personalName || tag == .placeName || tag == .organizationName
  }
}
