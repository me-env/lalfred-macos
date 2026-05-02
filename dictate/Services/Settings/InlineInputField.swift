import SwiftUI

struct InlineInputField: View {
  let title: String
  @Binding var text: String
  var controlHeight: CGFloat = 32
  var width: CGFloat? = nil
  var expandToFill: Bool = false
  var onSubmit: (() -> Void)? = nil

  var body: some View {
    TextField(title, text: $text)
      .textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.background)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(.separator.opacity(0.35), lineWidth: 1)
      )
      .onSubmit {
        onSubmit?()
      }
      .modifier(InputWidthModifier(width: width, expandToFill: expandToFill))
      .frame(height: controlHeight)
  }
}

private struct InputWidthModifier: ViewModifier {
  let width: CGFloat?
  let expandToFill: Bool

  func body(content: Content) -> some View {
    if let width {
      content.frame(width: width)
    } else if expandToFill {
      content.frame(maxWidth: .infinity)
    } else {
      content
    }
  }
}
