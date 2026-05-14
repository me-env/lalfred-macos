import SwiftUI


enum LalfredInputFieldStyle {
  case def
  case light
}


struct InlineInputField: View {
  let title: String
  let systemImage: String?
  
  @Binding var text: String
  
  var controlHeight: CGFloat
  var width: CGFloat?
  var expandToFill: Bool
  var onSubmit: (() -> Void)?
  var style: LalfredInputFieldStyle
  
  init(
    title: String,
    systemImage: String? = nil,
    text: Binding<String>,
    controlHeight: CGFloat = 32,
    width: CGFloat? = nil,
    expandToFill: Bool = false,
    onSubmit: (() -> Void)? = nil,
    style: LalfredInputFieldStyle = .def
  ) {
    self.title = title
    self.systemImage = systemImage
    self._text = text
    self.controlHeight = controlHeight
    self.width = width
    self.expandToFill = expandToFill
    self.onSubmit = onSubmit
    self.style = style
  }

  var body: some View {
    HStack {
      if let systemImage = self.systemImage {
        Image(systemName: systemImage)
      }
      TextField(title, text: $text)
        .onSubmit { onSubmit?() }
        .textFieldStyle(.plain)
        .modifier(InputWidthModifier(width: width, expandToFill: expandToFill))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      style == .def ? .quinary : .quaternary,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(style == .def ? 0.35 : 1), lineWidth: 1)
    )
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
