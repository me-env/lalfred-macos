import CoreGraphics

enum IndicatorBubbleContent: Equatable {
  case listening(level: CGFloat)
  case status(message: String)
}
