import SwiftUI
import AppKit
import Carbon.HIToolbox


private final class LocalKeyDownMonitor {
  private var monitorToken: Any?

  func start(handler: @escaping (NSEvent) -> Bool) {
    guard monitorToken == nil else { return }

    monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event) ? nil : event
    }
  }

  func stop() {
    guard let monitorToken else { return }
    NSEvent.removeMonitor(monitorToken)
    self.monitorToken = nil
  }

  deinit {
    stop()
  }
}

private final class LocalFlagsChangedMonitor {
  private var monitorToken: Any?

  func start(handler: @escaping (NSEvent) -> Bool) {
    guard monitorToken == nil else { return }

    monitorToken = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      handler(event) ? nil : event
    }
  }

  func stop() {
    guard let monitorToken else { return }
    NSEvent.removeMonitor(monitorToken)
    self.monitorToken = nil
  }

  deinit {
    stop()
  }
}

struct ShortcutInput: View {
  let label: String
  let storeKey: String
  @Binding var activeShortcutEditorID: String?
  private let shortcutStore: ShortcutDefaultsStore
  private let defaultShortcut: Shortcut

  @State private var capturedShortcut: Shortcut?
  @State private var pendingModifiers: ShortcutModifiers = []
  @State private var shortcutHovered: Bool = false
  @State private var clearHovered: Bool = false
  @State private var isCapturingKeys: Bool = false
  @State private var recordingPulse: Bool = false
  @State private var keyDownMonitor = LocalKeyDownMonitor()
  @State private var flagsChangedMonitor = LocalFlagsChangedMonitor()

  init(
    label: String,
    storeKey: String,
    defaultShortcut: Shortcut,
    activeShortcutEditorID: Binding<String?>
  ) {
    self.label = label
    self.storeKey = storeKey
    _activeShortcutEditorID = activeShortcutEditorID
    self.defaultShortcut = defaultShortcut
    let store = ShortcutDefaultsStore(key: storeKey)
    self.shortcutStore = store
    store.ensureDefault(defaultShortcut)
    _capturedShortcut = State(
      initialValue: store.load()
    )
  }
  
  func recordShortcut() {
    activeShortcutEditorID = storeKey
  }
  
  func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isCapturingKeys else { return false }

    if event.keyCode == UInt16(kVK_Escape) {
      pendingModifiers = []
      capturedShortcut = shortcutStore.load()
      activeShortcutEditorID = nil
      return true
    }

    if Self.modifierKeyCodes.contains(event.keyCode) {
      return true
    }

    pendingModifiers = []
    let shortcut = Shortcut(
      keyCode: event.keyCode,
      modifiers: ShortcutModifiers(eventModifierFlags: event.modifierFlags)
    )
    capturedShortcut = shortcut
    shortcutStore.save(shortcut)
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
    activeShortcutEditorID = nil
    return true
  }

  func handleFlagsChanged(_ event: NSEvent) -> Bool {
    guard isCapturingKeys else { return false }

    let modifiers = ShortcutModifiers(eventModifierFlags: event.modifierFlags)

    if modifiers.count >= 2 {
      pendingModifiers = modifiers
      capturedShortcut = Shortcut(keyCode: Shortcut.modifierOnlyKeyCode, modifiers: modifiers)
      return true
    }

    if !pendingModifiers.isEmpty && modifiers.isEmpty {
      let shortcut = Shortcut(keyCode: Shortcut.modifierOnlyKeyCode, modifiers: pendingModifiers)
      capturedShortcut = shortcut
      shortcutStore.save(shortcut)
      NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
      pendingModifiers = []
      activeShortcutEditorID = nil
      return true
    }

    return true
  }

  func clearShortcut() {
    activeShortcutEditorID = nil
    capturedShortcut = nil
    shortcutStore.remove()
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
  }

  func restoreDefaultShortcut() {
    activeShortcutEditorID = nil
    capturedShortcut = defaultShortcut
    shortcutStore.save(defaultShortcut)
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
  }

  func publishShortcutCaptureState(_ isCapturing: Bool) {
    NotificationCenter.default.post(
      name: .shortcutCaptureStateDidChange,
      object: nil,
      userInfo: [ShortcutNotificationUserInfoKey.isCapturing: isCapturing]
    )
  }
  
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
            isCapturingKeys
            ? Color.black.opacity(0.14)
            : shortcutHovered ? Color.primary.opacity(0.14) : .clear
          )
          .overlay {
            RoundedRectangle(cornerRadius: outerCornerRadius)
              .stroke(
                isCapturingKeys
                ? Color.black.opacity(0.55)
                : shortcutHovered ? Color.primary.opacity(0.75) : .clear,
                lineWidth: 0.5
              )
          }
      }
      .onTapGesture { self.recordShortcut() }
      .backgroundStyle(.clear)
  }
  
  var currentShortcut: some View {
    HStack(spacing: 6) {
      if isCapturingKeys {
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
      if let capturedShortcut {
        ForEach(capturedShortcut.labels, id: \.self) { token in
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
      .onTapGesture { clearShortcut() }
      .opacity(capturedShortcut == nil ? 0.45 : 1.0)
  }

  var restoreDefaultButton: some View {
    Button {
      restoreDefaultShortcut()
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
    .onChange(of: isCapturingKeys) { _, isCapturing in
      publishShortcutCaptureState(isCapturing)
      if isCapturing {
        pendingModifiers = []
        keyDownMonitor.start { event in
          handleKeyDown(event)
        }
        flagsChangedMonitor.start { event in
          handleFlagsChanged(event)
        }
      } else {
        pendingModifiers = []
        capturedShortcut = shortcutStore.load()
        keyDownMonitor.stop()
        flagsChangedMonitor.stop()
      }
    }
    .onChange(of: activeShortcutEditorID) { _, activeEditorID in
      let shouldCapture = activeEditorID == storeKey
      if isCapturingKeys != shouldCapture {
        isCapturingKeys = shouldCapture
      }
    }
    .onAppear {
      isCapturingKeys = activeShortcutEditorID == storeKey
      if isCapturingKeys {
        publishShortcutCaptureState(true)
      }
    }
    .onDisappear {
      if isCapturingKeys {
        publishShortcutCaptureState(false)
      }
      keyDownMonitor.stop()
      flagsChangedMonitor.stop()
    }
  }
}

private extension ShortcutInput {
  static let modifierKeyCodes: Set<UInt16> = [
    UInt16(kVK_Command),
    UInt16(kVK_RightCommand),
    UInt16(kVK_Shift),
    UInt16(kVK_RightShift),
    UInt16(kVK_Option),
    UInt16(kVK_RightOption),
    UInt16(kVK_Control),
    UInt16(kVK_RightControl),
    UInt16(kVK_CapsLock),
    UInt16(kVK_Function)
  ]
}

#Preview {
  ShortcutInput(
    label: "Toggle Recording",
    storeKey: AppDefaultsKey.shortcutToggleRecording,
    defaultShortcut: AppDefaultShortcuts.toggleRecording,
    activeShortcutEditorID: .constant(nil)
  )
  .padding()
}
