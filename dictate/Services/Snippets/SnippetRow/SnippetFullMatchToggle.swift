import SwiftUI

/// Toggles full match in one click. Shown on hover, and always while full match is on, so the
/// snippet's state is visible at a glance.
struct SnippetFullMatchToggle: View {
  let isVisible: Bool
  let isFullMatch: Bool
  let onToggleFullMatch: (Bool) -> Void

  var body: some View {
    Button {
      onToggleFullMatch(!isFullMatch)
    } label: {
      Label("Full match", systemImage: isFullMatch ? "checkmark.circle.fill" : "circle")
        .font(.caption.weight(.medium))
        .foregroundStyle(isFullMatch ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(isFullMatch ? 0.14 : 0))
        )
        .overlay(
          Capsule(style: .continuous)
            .stroke(isFullMatch ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.35), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .opacity(isVisible || isFullMatch ? 1 : 0)
    .disabled(!isVisible && !isFullMatch)
    .help(isFullMatch ? "Full match on: replaces only when the whole dictation is the trigger" : "Replace only when the whole dictation is the trigger")
  }
}

#Preview {
  VStack(spacing: 12) {
    SnippetFullMatchToggle(isVisible: true, isFullMatch: true, onToggleFullMatch: { _ in })
    SnippetFullMatchToggle(isVisible: true, isFullMatch: false, onToggleFullMatch: { _ in })
  }
  .padding()
}
