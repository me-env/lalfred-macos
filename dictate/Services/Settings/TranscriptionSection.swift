import SwiftUI

struct TranscriptionSection: View {
  @AppStorage(AppDefaultsKey.transcriptionProvider) private var rawProvider = TranscriptionProvider.defaultProvider.rawValue
  @AppStorage(AppDefaultsKey.transcriptEditScribeV2) private var scribeV2TranscriptEdit = ""
  @AppStorage(AppDefaultsKey.languageCodeScribeV2) private var scribeV2LanguageCode = ""
  @AppStorage(AppDefaultsKey.languageCodeVoxtral) private var voxtralLanguageCode = ""
  /// Key providers with no key saved, so the picker can say so for their models.
  @State private var providersMissingKey: Set<APIKeyProvider> = []
  @State private var apiKeys = APIKeyViewModel()
  /// The model list is open, or a model was just picked: the parameters look unstable.
  @State private var isPickingModel = false
  @State private var isSwitchingModel = false

  private var provider: TranscriptionProvider {
    TranscriptionProvider(rawValue: rawProvider) ?? .defaultProvider
  }

  var body: some View {
    VStack {
      VStack(alignment: .leading, spacing: 8) {
        ModelPicker(
          selection: provider,
          providersMissingKey: providersMissingKey,
          isPresented: $isPickingModel,
          onPick: pick
        )
        if providersMissingKey.contains(provider.apiKeyProvider) {
          missingAPIKeyRow
            .padding(.horizontal, 4)
        }
      }
      .padding(.bottom, 4)

      parametersSection
        .instability(isPickingModel || isSwitchingModel)
    }
    .task(id: apiKeys.refreshToken) {
      let missing = await Task.detached {
        Set(APIKeyProvider.allCases.filter { !Keychain().contains($0.key) })
      }.value
      guard !Task.isCancelled else { return }
      providersMissingKey = missing
    }
    .sheet(item: $apiKeys.editingProvider) { keyProvider in
      APIKeyEditorSheet(
        provider: keyProvider,
        onCancel: { apiKeys.cancelEditing() },
        onSave: { apiKey in apiKeys.save(apiKey, for: keyProvider) }
      )
    }
  }

  /// Switches model, with the parameters glitching a moment before they settle.
  private func pick(_ model: TranscriptionProvider) {
    isSwitchingModel = true
    rawProvider = model.rawValue
    Task {
      try? await Task.sleep(for: .seconds(0.4))
      isSwitchingModel = false
    }
  }

  private var parametersSection: some View {
    SectionBoxWithTitle("Model parameters", caption: caption) {
      VStack(alignment: .leading, spacing: 10) {
        mainLanguagePicker

        if provider.transcriptEditKey != nil {
          transcriptEditField
        }
      }
    }
  }

  private var caption: String {
    switch provider {
    case .scribeV2:
      return "Transcript edit applies your instruction to each transcript (up to 2000 characters). It adds 30% to the transcription cost."
    case .voxtral:
      return "Uses your Mistral AI key. Up to 100 dictionary words guide the spelling of names and terms."
    }
  }

  private var missingAPIKeyRow: some View {
    HStack {
      Label("No \(provider.apiKeyProvider.displayName) API key", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .font(.callout)
      Spacer()
      Button("Set API Key…") {
        apiKeys.beginEditing(provider.apiKeyProvider)
      }
    }
  }

  private var mainLanguagePicker: some View {
    Picker("Main language", selection: languageCodeBinding) {
      Text("Auto").tag("")
      Divider()
      ForEach(provider.languageCodes, id: \.self) { code in
        Text(TranscriptionLanguages.displayName(for: code)).tag(code)
      }
    }
  }

  private var languageCodeBinding: Binding<String> {
    switch provider {
    case .scribeV2:
      return $scribeV2LanguageCode
    case .voxtral:
      return $voxtralLanguageCode
    }
  }

  private var transcriptEditField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Transcript edit")
      TextField("e.g. Write numbers as digits", text: transcriptEditBinding, axis: .vertical)
        .lineLimit(2...5)
        .textFieldStyle(.roundedBorder)
    }
  }

  private var transcriptEditBinding: Binding<String> {
    Binding(
      get: { scribeV2TranscriptEdit },
      set: { scribeV2TranscriptEdit = String($0.prefix(TranscriptionSettings.transcriptEditMaxLength)) }
    )
  }
}
