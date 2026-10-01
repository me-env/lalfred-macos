import SwiftUI


struct IndicatorBubbleView: View {
  var viewModel: IndicatorViewModel
  
  private let cornerRadius: CGFloat = 18
  
  var body: some View {
    SpeechIndicatorView(
      content: viewModel.bubbleContent,
      shouldAnimateAppearance: viewModel.shouldAnimateAppearance
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.black)
        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
    }
  }
}

#Preview("Indicator Bubble - Listening") {
  Text("Hello world")
//  IndicatorBubbleView(viewModel: {
//    let vm = IndicatorViewModel()
//    vm.bubbleContent = .listening(level: 0.62)
//    vm.shouldAnimateAppearance = true
//    return vm
//  }())
//  .frame(width: 110, height: 45)
//  .padding()
}

#Preview("Indicator Bubble - Processing") {
  IndicatorBubbleView(viewModel: {
    let vm = IndicatorViewModel()
    vm.bubbleContent = .status(message: "Processing")
    return vm
  }())
  .frame(width: 110, height: 45)
  .padding()
}

#Preview("Indicator Bubble - Retrying") {
  IndicatorBubbleView(viewModel: {
    let vm = IndicatorViewModel()
    vm.bubbleContent = .status(message: "Retrying")
    return vm
  }())
  .frame(
    width: IndicatorPanelMetrics.retryingBubbleSize.width,
    height: IndicatorPanelMetrics.retryingBubbleSize.height
  )
  .padding()
}

#Preview("Hello world") {
  HStack {
    Text("Hello")
  }
}
