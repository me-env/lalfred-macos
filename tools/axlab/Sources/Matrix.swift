/// Cases from the matrix in `dictateTests/PasteContextFixtures/README.md`, always pasting
/// "Hello world". Each one starts from an empty field.
struct MatrixCase {
  enum Step {
    case type(String)
    case newline
    case left(Int)
  }

  let number: Int
  let steps: [Step]
  let expected: String
  let note: String
  var needsMultiline = false

  /// What the field holds once the steps ran.
  var content: String {
    steps.reduce(into: "") { text, step in
      switch step {
      case .type(let typed): text += typed
      case .newline: text += "\n"
      case .left: break
      }
    }
  }

  static let sample = "Hello world"

  /// Trimmed from 11: the dropped cases (3–6, 10, 11) never caught a reading failure the
  /// others didn't, over every method and app captured. What they varied (a space, period
  /// or comma before the cursor) is transformer logic, covered by PasteTextTransformerTests.
  /// Their fixtures stay in the unit tests. Numbers are kept so fixture names don't change.
  static let all: [MatrixCase] = [
    // Readers that pick up text from outside the field (placeholders, UI labels).
    MatrixCase(number: 1, steps: [], expected: "Hello world", note: "empty field"),
    // The base case: touching a word.
    MatrixCase(number: 2, steps: [.type("hey")], expected: " hello world", note: "after hey"),
    // Chromium leaves paragraph breaks out of offsets and ranges.
    MatrixCase(
      number: 7, steps: [.type("hey"), .newline], expected: "Hello world",
      note: "start of empty line 2", needsMultiline: true
    ),
    // Offsets drifting by one per paragraph before the cursor.
    MatrixCase(
      number: 8, steps: [.type("hey"), .newline, .type("there")], expected: " hello world",
      note: "after there (hey/there)", needsMultiline: true
    ),
    // Cursor at the end of a line followed by another (line-by-index reads the wrong line).
    MatrixCase(
      number: 9, steps: [.type("hey"), .newline, .type("there"), .left(6)], expected: " hello world",
      note: "end of line 1 (hey/there)", needsMultiline: true
    ),
  ]

  static func cases(multiline: Bool) -> [MatrixCase] {
    all.filter { multiline || !$0.needsMultiline }
  }
}
