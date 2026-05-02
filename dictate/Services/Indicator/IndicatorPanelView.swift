import SwiftUI


struct IndicatorBubbleView: View {
    var viewModel: IndicatorPanelController.IndicatorViewModel

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
    IndicatorBubbleView(viewModel: {
        let vm = IndicatorPanelController.IndicatorViewModel()
        vm.bubbleContent = .listening(level: 0.62)
        vm.shouldAnimateAppearance = true
        return vm
    }())
    .frame(width: 110, height: 45)
    .padding()
}

#Preview("Indicator Bubble - Processing") {
    IndicatorBubbleView(viewModel: {
        let vm = IndicatorPanelController.IndicatorViewModel()
        vm.bubbleContent = .status(message: "Processing")
        return vm
    }())
    .frame(width: 110, height: 45)
    .padding()
}
