import SwiftUI

struct StatusImageView: View {
  let statusImage: Image
  let message: String

  var body: some View {
    statusImage
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(statusForegroundColor)
      .symbolRenderingMode(.hierarchical)
      .offset(y: statusYOffset)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var statusForegroundColor: Color {
    switch normalizedStatusMessage {
    case "cancel":
      return Color(red: 1.0, green: 0.72, blue: 0.72)
    default:
      return .white
    }
  }

  private var statusYOffset: CGFloat {
    switch normalizedStatusMessage {
    case "pasted":
      return -1
    default:
      return 0
    }
  }

  private var normalizedStatusMessage: String {
    message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
