import SwiftUI

struct SectionBox<Content: View>: View {
  @ViewBuilder let content: () -> Content
  
  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }
  
  var body: some View {
    content()
      .modifier(SectionBoxCardStyle())
  }
}

struct SectionBoxWithTitle<Content: View>: View {
  let title: String
  let caption: String?
  @ViewBuilder let content: () -> Content
  
  init(_ title: String, caption: String? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.caption = caption
    self.content = content
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      
      content()
      
      if let caption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .modifier(SectionBoxCardStyle())
  }
}

private struct SectionBoxCardStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        .quaternary.opacity(0.2),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.gray.opacity(0.2), lineWidth: 1)
      )
  }
}
