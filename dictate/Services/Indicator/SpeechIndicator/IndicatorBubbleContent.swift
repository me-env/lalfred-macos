enum IndicatorBubbleContent: Equatable {
  case preparing
  case listening(levels: ListeningLevels)
  case status(message: String)
}
