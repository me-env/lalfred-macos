//
//  ShortcutInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

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

struct ShortcutInput: View {
  private static let fallbackShortcut = Shortcut(
    keyCode: KeyCode.from(character: " ") ?? UInt16(49),
    modifiers: [.control, .option]
  )
  private static let shortcutStore = ShortcutDefaultsStore(key: "shortcut.toggleRecording")
  
  @State private var capturedShortcut: Shortcut
  @State private var hovered: Bool = false
  @State private var isCapturingKeys: Bool = false
  @State private var recordingPulse: Bool = false
  @State private var keyDownMonitor = LocalKeyDownMonitor()
  
  init() {
    _capturedShortcut = State(
      initialValue: Self.shortcutStore.load() ?? Self.fallbackShortcut
    )
  }
  
  func recordShortcut() {
    isCapturingKeys = true
  }
  
  func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isCapturingKeys else { return false }

    if event.keyCode == UInt16(kVK_Escape) {
      isCapturingKeys = false
      return true
    }

    if Self.modifierKeyCodes.contains(event.keyCode) {
      return true
    }

    let shortcut = Shortcut(
      keyCode: event.keyCode,
      modifiers: ShortcutModifiers(eventModifierFlags: event.modifierFlags)
    )
    capturedShortcut = shortcut
    Self.shortcutStore.save(shortcut)
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
    isCapturingKeys = false
    return true
  }
  
  let innerRecCorderRadier: CGFloat = 4
  let padding: CGFloat = 4
  
  var outerCornerRadius: CGFloat {
    innerRecCorderRadier + padding
  }
  
  func onHover(isHovered: Bool) {
    print("hover \(isHovered)")
    self.hovered = isHovered
  }
  
  var shortcutSection: some View {
    currentShortcut
      .padding(.all, padding)
      .onHover(perform: onHover)
      .background {
        RoundedRectangle(cornerRadius: outerCornerRadius)
          .fill(
            isCapturingKeys
              ? Color.black.opacity(0.14)
              : hovered ? Color.primary.opacity(0.14) : .clear
          )
          .overlay {
            RoundedRectangle(cornerRadius: outerCornerRadius)
              .stroke(
                isCapturingKeys
                  ? Color.black.opacity(0.55)
                  : hovered ? Color.primary.opacity(0.75) : .clear,
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
      ForEach(capturedShortcut.toLabels(), id: \.self) { token in
        shortcutToken(token)
      }
    }
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
    SectionBox("Keyboard Shortcut", caption: "Starts and stops recording") {
      HStack {
        Text("Toggle Recording")
        Spacer()
        shortcutSection
      }
    }
    .onChange(of: isCapturingKeys) { _, isCapturing in
      if isCapturing {
        keyDownMonitor.start { event in
          handleKeyDown(event)
        }
      } else {
        keyDownMonitor.stop()
      }
    }
    .onDisappear {
      keyDownMonitor.stop()
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
  ShortcutInput()
    .padding()
}
