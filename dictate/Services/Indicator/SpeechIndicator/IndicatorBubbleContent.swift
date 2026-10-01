import CoreGraphics

enum IndicatorBubbleContent: Equatable {
  case preparing
  case listening(level: CGFloat)
  case status(message: String)
}
