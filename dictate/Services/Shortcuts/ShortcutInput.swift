import SwiftUI

struct ShortcutInput: View {
  let label: String
  let recorder: ShortcutRecorder
  @Binding var activeShortcutEditorID: String?

  @State private var shortcutHovered: Bool = false
  @State private var clearHovered: Bool = false
  @State private var recordingPulse: Bool = false

  let innerRecCorderRadier: CGFloat = 4
  let padding: CGFloat = 4

  var outerCornerRadius: CGFloat {
    innerRecCorderRadier + padding
  }

  func onShortcutHover(isHovered: Bool) {
    self.shortcutHovered = isHovered
  }

  func onClearHover(isHovered: Bool) {
    self.clearHovered = isHovered
  }

  var shortcutSection: some View {
    currentShortcut
      .padding(.all, padding)
      .onHover(perform: onShortcutHover)
      .background {
        RoundedRectangle(cornerRadius: outerCornerRadius)
          .fill(
            recorder.isCapturing
            ? Color.black.opacity(0.14)
            : shortcutHovered ? Color.primary.opacity(0.14) : .clear
          )
          .overlay {
            RoundedRectangle(cornerRadius: outerCornerRadius)
              .stroke(
                recorder.isCapturing
                ? Color.black.opacity(0.55)
                : shortcutHovered ? Color.primary.opacity(0.75) : .clear,
                lineWidth: 0.5
              )
          }
      }
      .onTapGesture { activeShortcutEditorID = recorder.id }
      .backgroundStyle(.clear)
  }

  var currentShortcut: some View {
    HStack(spacing: 6) {
      if recorder.isCapturing {
        recordingIndicator
      }

      shortcutTokens
    }
  }

  var recordingIndicator: some View {
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

  var shortcutTokens: some View {
    HStack(spacing: 3) {
      if let captured = recorder.shortcut {
        ForEach(captured.labels, id: \.self) { token in
          shortcutToken(token)
        }
      } else {
        notSetText
      }
    }
  }

  var clearButton: some View {
    Image(systemName: "xmark")
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(clearHovered ? .primary : .secondary)
      .padding(.all, 4)
      .contentShape(Rectangle())
      .onHover(perform: onClearHover)
      .onTapGesture {
        activeShortcutEditorID = nil
        recorder.clear()
      }
      .opacity(recorder.shortcut == nil ? 0.45 : 1.0)
  }

  var restoreDefaultButton: some View {
    Button {
      activeShortcutEditorID = nil
      recorder.restoreDefault()
    } label: {
      Image(systemName: "arrow.counterclockwise")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18, height: 18)
    }
    .buttonStyle(.plain)
  }

  var notSetText: some View {
    Text("Not set")
      .font(.system(size: 10, weight: .semibold, design: .rounded))
      .padding(.horizontal, 4)
      .padding(.vertical, 3)
  }

  func shortcutToken(_ token: String) -> some View {
    Text(token)
      .font(.system(size: 10, weight: .semibold, design: .rounded))
      .padding(.horizontal, 4)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: innerRecCorderRadier)
          .fill(Color.secondary.opacity(0.18))
      )
  }

  var body: some View {
    HStack {
      Text(label)
      Spacer()
      shortcutSection
      clearButton
    }
    .onChange(of: activeShortcutEditorID) { _, activeID in
      if activeID == recorder.id {
        recorder.begin()
      } else {
        recorder.cancel()
      }
    }
    .onChange(of: recorder.isCapturing) { _, isCapturing in
      if !isCapturing && activeShortcutEditorID == recorder.id {
        activeShortcutEditorID = nil
      }
    }
    .onDisappear {
      recorder.cancel()
    }
  }
}

#Preview {
  ShortcutInput(
    label: "Toggle Recording",
    recorder: ShortcutRecorder(
      id: AppDefaultsKey.shortcutToggleRecording,
      defaultShortcut: AppDefaultShortcuts.toggleRecording
    ),
    activeShortcutEditorID: .constant(nil)
  )
  .padding()
}
