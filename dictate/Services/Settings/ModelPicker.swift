import SwiftUI


/// A large card showing the selected transcription model; clicking it lists the models in a
/// popover, with their company and whether its API key is missing.
struct ModelPicker: View {
  let selection: TranscriptionProvider
  let providersMissingKey: Set<APIKeyProvider>
  @Binding var isPresented: Bool
  let onPick: (TranscriptionProvider) -> Void

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 12) {
        LogoBeside(provider: selection.apiKeyProvider, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text(selection.displayName)
              .font(.title3.weight(.semibold))
            ModelSubtitle(model: selection, isMissingKey: providersMissingKey.contains(selection.apiKeyProvider))
          }
        }

        Spacer()

        Image(systemName: "chevron.up.chevron.down")
          .foregroundStyle(.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .background(.quaternary.opacity(isPresented ? 0.45 : 0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(isPresented ? Color.accentColor.opacity(0.6) : .gray.opacity(0.2), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help("Change the transcription model")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(TranscriptionProvider.allCases) { model in
          ModelRow(
            model: model,
            isSelected: model == selection,
            isMissingKey: providersMissingKey.contains(model.apiKeyProvider)
          ) {
            isPresented = false
            if model != selection { onPick(model) }
          }
        }
      }
      .padding(6)
      .frame(width: 320)
    }
  }
}


private struct ModelRow: View {
  let model: TranscriptionProvider
  let isSelected: Bool
  let isMissingKey: Bool
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        LogoBeside(provider: model.apiKeyProvider, spacing: 10) {
          VStack(alignment: .leading, spacing: 1) {
            Text(model.displayName)
              .fontWeight(.medium)
            ModelSubtitle(model: model, isMissingKey: isMissingKey)
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .background(
        isHovered ? Color.secondary.opacity(0.15) : .clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}


/// "ElevenLabs", or "Mistral AI · No API key".
private struct ModelSubtitle: View {
  let model: TranscriptionProvider
  let isMissingKey: Bool

  var body: some View {
    HStack(spacing: 4) {
      Text(model.apiKeyProvider.displayName)
        .foregroundStyle(.secondary)
      if isMissingKey {
        Text("· No API key")
          .foregroundStyle(.orange)
      }
    }
    .font(.caption)
  }
}


/// A company logo next to some text, as a square exactly as tall as the text: its top lines
/// up with the first line and its bottom with the last.
private struct LogoBeside<Content: View>: View {
  let provider: APIKeyProvider
  let spacing: CGFloat
  @ViewBuilder let content: Content
  @State private var textHeight: CGFloat = 0

  var body: some View {
    HStack(spacing: spacing) {
      ModelLogo(provider: provider, size: textHeight)
      content
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
    }
  }
}


/// The company logo on a rounded square tile.
struct ModelLogo: View {
  let provider: APIKeyProvider
  let size: CGFloat

  var body: some View {
    Image(provider.logoImageName)
      .resizable()
      .scaledToFit()
      .padding(size * 0.2)
      .frame(width: size, height: size)
      .background(.background, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
          .strokeBorder(.gray.opacity(0.25), lineWidth: 1)
      )
  }
}
