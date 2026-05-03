import SwiftUI

#Preview("Listening (Low)") {
  SpeechIndicatorView(
    content: .listening(level: 0.2),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Listening (High)") {
  SpeechIndicatorView(
    content: .listening(level: 0.9),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Processing") {
  SpeechIndicatorView(
    content: .status(message: "processing"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Cancel") {
  SpeechIndicatorView(
    content: .status(message: "cancel"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Pasted") {
  SpeechIndicatorView(
    content: .status(message: "pasted"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Text Fallback") {
  SpeechIndicatorView(
    content: .status(message: "Network error while processing"),
    shouldAnimateAppearance: false
  )
  .padding()
}
