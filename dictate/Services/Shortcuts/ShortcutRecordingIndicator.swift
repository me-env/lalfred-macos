import SwiftUI

struct ShortcutRecordingIndicator: View {
  @State private var recordingPulse: Bool = false

  var body: some View {
    Circle()
      .fill(.red)
      .frame(width: 8, height: 8)
      .scaleEffect(recordingPulse ? 1.0 : 0.65)
      .opacity(recordingPulse ? 1.0 : 0.55)
      .animation(
        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
        value: recordingPulse
      )
      .onAppear { recordingPulse = true }
      .onDisappear { recordingPulse = false }
  }
}

#Preview {
  ShortcutRecordingIndicator()
    .padding()
}
