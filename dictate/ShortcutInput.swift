//
//  ShortcutInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI

struct ShortcutInput: View {
  @State var shortcutKeys: String = ""
  @State var recordingShortcut: Bool = false
  @FocusState private var isCapturingKeys: Bool

  func recordShortcut() {
    recordingShortcut = true
    isCapturingKeys = true
  }

  func onKeyPress(key: KeyPress) -> KeyPress.Result {
    guard recordingShortcut else { return .ignored }
    print("\(key) pressed")
    recordingShortcut = false
    isCapturingKeys = false
    return KeyPress.Result.handled
  }
  
  func onModifierKeysChanged(ev1: EventModifiers, ev2: EventModifiers) {
    print("\(ev1) \(ev2)")
  }

  var sectionTitle: some View {
    VStack(alignment: .leading) {
      Text("Toggle Recording").font(.default)
      Text("Starts and stops recordings").font(.caption)
    }
  }
  
  var shortcutSection: some View {
    Button(action: self.recordShortcut) {
      Text(recordingShortcut ? "..." : "Record")
        .frame(width: 64)
    }
    .disabled(recordingShortcut)
    .focusable()
    .focused($isCapturingKeys)
    .onKeyPress(phases: [.down], action: self.onKeyPress)
    .onModifierKeysChanged(onModifierKeysChanged)
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
