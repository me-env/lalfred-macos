import SwiftUI

struct ShortcutInput: View {
  let label: String
  let store: ShortcutStore
  @Binding var activeShortcutEditorID: String?

  @State private var recorder: ShortcutRecorder
  @State private var shortcutHovered: Bool = false
  @State private var clearHovered: Bool = false

  let innerRecCorderRadier: CGFloat = 4
  let padding: CGFloat = 4

  init(
    label: String,
    store: ShortcutStore,
    activeShortcutEditorID: Binding<String?>
  ) {
    self.label = label
    self.store = store
    _activeShortcutEditorID = activeShortcutEditorID
    _recorder = State(initialValue: ShortcutRecorder(store: store))
  }

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
      .onTapGesture { activeShortcutEditorID = store.key }
      .backgroundStyle(.clear)
  }

  var currentShortcut: some View {
    HStack(spacing: 6) {
      if recorder.isCapturing {
        ShortcutRecordingIndicator()
      }

      shortcutTokens
    }
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
      if activeID == store.key {
        recorder.begin()
      } else {
        recorder.cancel()
      }
    }
    .onChange(of: recorder.isCapturing) { _, isCapturing in
      if !isCapturing && activeShortcutEditorID == store.key {
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
    store: ShortcutStore(key: AppDefaultsKey.shortcutToggleRecording),
    activeShortcutEditorID: .constant(nil)
  )
  .padding()
}
