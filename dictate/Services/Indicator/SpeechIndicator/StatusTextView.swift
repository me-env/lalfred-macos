import SwiftUI

struct StatusTextView: View {
  let message: String

  var body: some View {
    Text(message)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .lineLimit(3)
      .multilineTextAlignment(.center)
      .minimumScaleFactor(0.8)
      .foregroundStyle(.white)
      .frame(maxWidth: textMaxWidth)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var textMaxWidth: CGFloat {
    220
  }
}
