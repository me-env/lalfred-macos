import SwiftUI

struct RowDeleteButton: View {
  let helpText: String
  let isVisible: Bool
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      Image(systemName: "xmark.circle")
        .foregroundStyle(Color.red)
    }
    .buttonStyle(.borderless)
    .opacity(isVisible ? 1 : 0)
    .disabled(!isVisible)
    .help(helpText)
  }
}

struct RowDeleteMenuButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      Label(title, systemImage: "xmark.circle")
    }
  }
}
