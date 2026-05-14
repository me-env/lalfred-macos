import SwiftUI

private let fullMatchToggleTitle = "Full match"


struct FullSentenceMatchLabel: View {
  @State private var isTooltipPresented = false
  @State private var isHovered = false

  var body: some View {
    Button {
      isTooltipPresented = true
    } label: {
      HStack(spacing: 4) {
        Text(fullMatchToggleTitle)

        Image(systemName: "info.circle")
          .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.accentColor.opacity(isHovered ? 0.08 : 0))
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .animation(.easeInOut(duration: 0.12), value: isHovered)
    .popover(isPresented: $isTooltipPresented, arrowEdge: .bottom) {
      FullSentenceMatchTooltipView()
        .frame(width: 420)
        .padding(14)
    }
  }
}


#Preview {
  SnippetConfigurationMenu(
    isVisible: false,
    isFullMatch: false,
    onToggleFullMatch: { _ in }
  )
  .padding()
}
