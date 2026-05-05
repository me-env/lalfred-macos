import Foundation
import CoreGraphics

enum IndicatorPanelMetrics {
  static let compactBubbleSize = CGSize(width: 55, height: 22.5)
  static let expandedIndicatorScale: CGFloat = 1.3
  static let indicatorResizeDuration: TimeInterval = 0.2
  static let indicatorResizeOvershootFactor: CGFloat = 0.2

  static let expandedTextBubbleMinWidth: CGFloat = 176
  static let expandedTextBubbleMaxWidth: CGFloat = 300
  static let expandedTextBubbleMaxHeight: CGFloat = 112
  static let expandedTextBubbleMinHeight: CGFloat = 58

  static let commandPanelWidth: CGFloat = 230
  static let commandPanelInitialHeight: CGFloat = 200
  static let commandPanelMinHeight: CGFloat = 88
  static let commandPanelMaxHeight: CGFloat = 700
  static let commandPanelSize = CGSize(width: commandPanelWidth, height: commandPanelInitialHeight)
  static let panelGap: CGFloat = 6
  static let topInset: CGFloat = 20
}
