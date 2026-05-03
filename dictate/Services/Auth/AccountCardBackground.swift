import SwiftUI
import AppKit

extension View {
  /// Shared chrome for the "card" containers in the Account tab. Wraps the
  /// content in padding and a rounded, subtly-stroked background.
  func accountCardBackground() -> some View {
    padding()
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
  }
}
