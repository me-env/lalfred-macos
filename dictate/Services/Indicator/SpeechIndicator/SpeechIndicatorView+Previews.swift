import SwiftUI

#Preview("Preparing") {
  SpeechIndicatorView(
    content: .preparing,
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Listening (Low)") {
  SpeechIndicatorView(
    content: .listening(levels: ListeningLevels(clamping: [0.2, 0.15, 0.1, 0.05, 0, 0, 0, 0])),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Listening (High)") {
  SpeechIndicatorView(
    content: .listening(levels: ListeningLevels(clamping: [0.5, 0.9, 0.7, 0.4, 0.6, 0.3, 0, 0])),
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

#Preview("Status: Retrying") {
  SpeechIndicatorView(
    content: .status(message: "Retrying"),
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
