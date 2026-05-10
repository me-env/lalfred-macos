import SwiftUI

struct RowDeleteButton: View {
  let helpText: String
  let isVisible: Bool
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      Image(systemName: "xmark.circle")
        .foregroundStyle(isVisible ? Color.red : Color.clear)
    }
    .buttonStyle(.borderless)
    .help(helpText)
  }
}
