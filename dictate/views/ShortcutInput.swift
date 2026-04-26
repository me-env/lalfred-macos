//
//  ShortcutInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI

struct ShortcutInput: View {
  private static let fallbackShortcut = Shortcut(
    keyCode: KeyCode.from(character: " ") ?? UInt16(49),
    modifiers: [.control, .option]
  )
  private static let shortcutStore = ShortcutDefaultsStore(key: "shortcut.toggleRecording")
  
  @State private var capturedShortcut: Shortcut
  @State private var hovered: Bool = false
  @FocusState private var isCapturingKeys: Bool
  
  init() {
    _capturedShortcut = State(
      initialValue: Self.shortcutStore.load() ?? Self.fallbackShortcut
    )
  }
  
  func recordShortcut() {
    isCapturingKeys = true
  }
  
  func onKeyPress(key: KeyPress) -> KeyPress.Result {
    guard isCapturingKeys else { return .ignored }
    guard let character = key.characters.first,
          let keyCode = KeyCode.from(character: character) else {
      return .ignored
    }
    
    let shortcut = Shortcut(
      keyCode: keyCode,
      modifiers: ShortcutModifiers(eventModifiers: key.modifiers)
    )
    capturedShortcut = shortcut
    Self.shortcutStore.save(shortcut)
    isCapturingKeys = false
    return .handled
  }
  
  let innerRecCorderRadier: CGFloat = 4
  let padding: CGFloat = 4
  
  var sectionTitle: some View {
    VStack(alignment: .leading) {
      Text("Toggle Recording").font(.default)
      Text("Starts and stops recordings").font(.caption)
    }
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
        RoundedRectangle(cornerRadius: innerRecCorderRadier + padding)
          .foregroundStyle(hovered || isCapturingKeys ? .black : .clear)
      }
      .onTapGesture {
        self.recordShortcut()
      }
      .backgroundStyle(.clear)
      .disabled(isCapturingKeys)
      .focusable()
      .focused($isCapturingKeys)
      .onKeyPress(phases: [.down], action: self.onKeyPress)
  }
  
  var currentShortcut: some View {
    Group {
      HStack(spacing: 3) {
        ForEach(capturedShortcut.toLabels(), id: \.self) { token in
          Text(token)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
              RoundedRectangle(cornerRadius: innerRecCorderRadier)
                .fill(Color.secondary.opacity(0.18))
            )
        }
      }
    }
  }
  
  var body: some View {
    HStack {
      sectionTitle
      Spacer()
      shortcutSection
    }
  }
}

#Preview {
  ShortcutInput()
    .padding()
}
