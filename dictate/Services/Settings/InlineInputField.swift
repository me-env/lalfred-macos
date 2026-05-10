import SwiftUI

enum LalfredInputFieldStyle {
  case def
  case light
}

struct InlineInputField: View {
  let title: String
  @Binding var text: String
  var controlHeight: CGFloat = 32
  var width: CGFloat? = nil
  var expandToFill: Bool = false
  var onSubmit: (() -> Void)? = nil
  var style: LalfredInputFieldStyle = .def

  var body: some View {
    TextField(title, text: $text)
      .textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
//      .background(
//        RoundedRectangle(cornerRadius: 8, style: .continuous)
//          .fill(style == .def ? .background : .quaternary.opacity(0.2))
//      )
      .background(
        style == .def ? .quinary : .quaternary,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(.separator.opacity(style == .def ? 0.35 : 1), lineWidth: 1)
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


#Preview {
  VStack {
    InlineInputField(
      title: "Username",
      text: Binding(get: {"oui"}, set: { _ in }),
      style: LalfredInputFieldStyle.def
    )
    .padding()
    InlineInputField(
      title: "Username",
      text: Binding(get: {"oui"}, set: { _ in }),
      style: LalfredInputFieldStyle.light
    )
    .padding()
  }
}
