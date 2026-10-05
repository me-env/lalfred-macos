import SwiftUI


/// Loops through a few pastes into a mock text field: what was dictated, the text already
/// before the cursor, and what actually gets pasted, with the adjusted part highlighted.
/// Each example takes about 8 seconds.
struct ContextPasteAnimation: View {
  private struct Example {
    /// Text before the cursor in the field.
    let before: String
    let dictated: String
    let pasted: String
    let explanation: String
  }

  private static let examples = [
    Example(
      before: "I'll send you the report",
      dictated: "Tomorrow morning",
      pasted: " tomorrow morning",
      explanation: "Continues the sentence: adds a space and lowercases."
    ),
    Example(
      before: "The meeting went well.",
      dictated: "Let's plan the next one",
      pasted: " Let's plan the next one",
      explanation: "New sentence: adds a space and keeps the capital."
    ),
    Example(
      before: "Can we talk about it ",
      dictated: "Later today",
      pasted: "later today",
      explanation: "A space is already there: just lowercases."
    ),
    Example(
      before: "",
      dictated: "Thanks for your help",
      pasted: "Thanks for your help",
      explanation: "Start of the field: pasted as dictated."
    ),
  ]

  private enum Phase {
    case waiting, dictating, pasted
  }

  private static let height: CGFloat = 104

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var exampleIndex = 0
  @State private var phase = Phase.waiting
  @State private var cursorVisible = true

  private var example: Example { Self.examples[exampleIndex] }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      dictationBubble
      field
      Text(phase == .pasted ? example.explanation : " ")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    // Fixed, so the settings below never move as the examples change.
    .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
    .task { await loop() }
    .task { await blinkCursor() }
  }

  private var dictationBubble: some View {
    HStack(spacing: 6) {
      Image(systemName: "mic.fill")
      Text("“\(example.dictated)”")
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Color.accentColor.opacity(0.15), in: Capsule())
    .opacity(phase == .dictating ? 1 : 0)
    .offset(y: phase == .dictating || reduceMotion ? 0 : -6)
  }

  private var field: some View {
    HStack(spacing: 0) {
      Text(fieldText)
        .lineLimit(1)
      Rectangle()
        .fill(Color.accentColor)
        .frame(width: 2, height: 16)
        .opacity(cursorVisible ? 1 : 0)
      Spacer(minLength: 0)
    }
    .font(.system(.body, design: .rounded))
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
    )
  }

  /// The text before the cursor, then the pasted part highlighted (its leading space shows
  /// as a highlighted gap).
  private var fieldText: AttributedString {
    var text = AttributedString(example.before)
    guard phase == .pasted else { return text }
    var pasted = AttributedString(example.pasted)
    pasted.backgroundColor = Color.accentColor.opacity(0.25)
    text.append(pasted)
    return text
  }

  private func loop() async {
    try? await Task.sleep(for: .seconds(1.8))
    while !Task.isCancelled {
      await step(holding: 2.4) { phase = .dictating }
      await step(holding: 4.2) { phase = .pasted }
      // The next example and its phase change together, so it starts with only the text
      // before the cursor (not briefly with its pasted part, then without it).
      await step(holding: 1.8) {
        exampleIndex = (exampleIndex + 1) % Self.examples.count
        phase = .waiting
      }
    }
  }

  private func step(holding seconds: Double, _ change: () -> Void) async {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6), change)
    try? await Task.sleep(for: .seconds(seconds))
  }

  private func blinkCursor() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(0.55))
      cursorVisible.toggle()
    }
  }
}


#Preview {
  ContextPasteAnimation()
    .padding()
    .frame(width: 420)
}
