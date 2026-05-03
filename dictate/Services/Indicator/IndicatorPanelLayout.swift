import AppKit

@MainActor
enum IndicatorPanelLayout {
  static let compactBubbleSize = CGSize(width: 55, height: 22.5)
  static let modeSwitcherIndicatorScale: CGFloat = 1.3
  static let modeSwitcherResizeDuration: TimeInterval = 0.2
  static let modeSwitcherOvershootFactor: CGFloat = 0.2

  static let expandedTextBubbleMinWidth: CGFloat = 176
  static let expandedTextBubbleMaxWidth: CGFloat = 300
  static let expandedTextBubbleMaxHeight: CGFloat = 112
  static let expandedTextBubbleMinHeight: CGFloat = 58

  static let commandPanelSize = CGSize(width: 320, height: 200)
  static let panelGap: CGFloat = 6
  static let topInset: CGFloat = 20

  static func indicatorFrame(for size: CGSize) -> NSRect {
    guard let screen = NSScreen.main else {
      return NSRect(origin: .zero, size: size)
    }
    let visibleFrame = screen.visibleFrame
    let x = visibleFrame.midX - (size.width / 2)
    let y = visibleFrame.maxY - topInset - size.height
    return NSRect(x: x, y: y, width: size.width, height: size.height)
  }

  static func commandFrame(below indicatorFrame: NSRect) -> NSRect {
    let x = indicatorFrame.midX - (commandPanelSize.width / 2)
    let y = indicatorFrame.minY - panelGap - commandPanelSize.height
    return NSRect(x: x, y: y, width: commandPanelSize.width, height: commandPanelSize.height)
  }

  static func indicatorSize(for content: IndicatorBubbleContent) -> CGSize {
    switch content {
    case .listening:
      return compactBubbleSize
    case .status(let message):
      return statusSize(for: message)
    }
  }

  private static func statusSize(for message: String) -> CGSize {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "processing" || normalized == "cancel" || normalized == "pasted" || normalized == "nospeech" {
      return compactBubbleSize
    }
    let textSize = measuredTextSize(for: message)
    let width = min(expandedTextBubbleMaxWidth, max(expandedTextBubbleMinWidth, textSize.width + 56))
    let height = min(expandedTextBubbleMaxHeight, max(expandedTextBubbleMinHeight, textSize.height + 30))
    return CGSize(width: width, height: height)
  }

  private static func measuredTextSize(for message: String) -> CGSize {
    let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    let rect = (message as NSString).boundingRect(
      with: CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    )
    return CGSize(width: ceil(rect.width), height: ceil(rect.height))
  }
}
