import AppKit

enum IndicatorPanelLayout {
  static func indicatorFrame(for size: CGSize) -> NSRect {
    guard let screen = NSScreen.main else {
      return NSRect(origin: .zero, size: size)
    }

    let visibleFrame = screen.visibleFrame
    let x = visibleFrame.midX - (size.width / 2)
    let y = visibleFrame.maxY - IndicatorPanelMetrics.topInset - size.height
    return NSRect(x: x, y: y, width: size.width, height: size.height)
  }

  static func commandFrame(below indicatorFrame: NSRect) -> NSRect {
    let x = indicatorFrame.midX - (IndicatorPanelMetrics.commandPanelSize.width / 2)
    let y = indicatorFrame.minY - IndicatorPanelMetrics.panelGap - IndicatorPanelMetrics.commandPanelSize.height
    return NSRect(
      x: x,
      y: y,
      width: IndicatorPanelMetrics.commandPanelSize.width,
      height: IndicatorPanelMetrics.commandPanelSize.height
    )
  }

  static func indicatorSize(for content: IndicatorBubbleContent) -> CGSize {
    switch content {
    case .listening:
      return IndicatorPanelMetrics.compactBubbleSize
    case .status(let message):
      return statusSize(for: message)
    }
  }

  private static func statusSize(for message: String) -> CGSize {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "processing" || normalized == "cancel" || normalized == "pasted" || normalized == "nospeech" {
      return IndicatorPanelMetrics.compactBubbleSize
    }

    let textSize = measuredTextSize(for: message)
    let width = min(
      IndicatorPanelMetrics.expandedTextBubbleMaxWidth,
      max(IndicatorPanelMetrics.expandedTextBubbleMinWidth, textSize.width + 56)
    )
    let height = min(
      IndicatorPanelMetrics.expandedTextBubbleMaxHeight,
      max(IndicatorPanelMetrics.expandedTextBubbleMinHeight, textSize.height + 30)
    )
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
