import Observation

@Observable
final class IndicatorViewModel {
  var bubbleContent: IndicatorBubbleContent = .status(message: "")
  var shouldAnimateAppearance = false
}
