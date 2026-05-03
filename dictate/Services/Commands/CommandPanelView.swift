import SwiftUI


struct CommandPanelView: View {
    var viewModel: CommandViewModel

    private let cornerRadius: CGFloat = 18

    var body: some View {
        ModeSwitcherInputView(
            query: Binding(
                get: { viewModel.query },
                set: { newQuery in
                    viewModel.query = newQuery
                    viewModel.suggestions = viewModel.filteredSuggestions(for: newQuery)
                }
            ),
            suggestions: viewModel.suggestions,
            onSubmit: { value in viewModel.onSubmit?(value) },
            onDismiss: { viewModel.onDismiss?() }
        )
        .padding()
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }
}

#Preview("Command Panel") {
    CommandPanelView(viewModel: {
        let vm = CommandViewModel(modeCatalog: ModeCatalog())
        vm.reset()
        return vm
    }())
    .frame(width: 320, height: 200)
    .padding()
}
