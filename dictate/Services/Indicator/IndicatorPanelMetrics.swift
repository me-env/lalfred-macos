import Foundation
import CoreGraphics

enum IndicatorPanelMetrics {
  static let compactBubbleSize = CGSize(width: 55, height: 22.5)
  static let modeSwitcherIndicatorScale: CGFloat = 1.3
  static let modeSwitcherResizeDuration: TimeInterval = 0.2
  static let modeSwitcherOvershootFactor: CGFloat = 0.2

  static let expandedTextBubbleMinWidth: CGFloat = 176
  static let expandedTextBubbleMaxWidth: CGFloat = 300
  static let expandedTextBubbleMaxHeight: CGFloat = 112
  static let expandedTextBubbleMinHeight: CGFloat = 58

  static let commandPanelSize = CGSize(width: 320, height: 700)
  static let panelGap: CGFloat = 6
  static let topInset: CGFloat = 20
}
