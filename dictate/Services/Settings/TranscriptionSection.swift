import SwiftUI

struct TranscriptionSection: View {
  @AppStorage(AppDefaultsKey.transcriptionProvider) private var rawProvider = TranscriptionProvider.defaultProvider.rawValue
  @AppStorage(AppDefaultsKey.transcriptEditScribeV2) private var scribeV2TranscriptEdit = ""
  @AppStorage(AppDefaultsKey.transcriptEditScribeV2Realtime) private var realtimeTranscriptEdit = ""
  @AppStorage(AppDefaultsKey.languageCodeScribeV2) private var scribeV2LanguageCode = ""
  @AppStorage(AppDefaultsKey.realtimeLanguageCode) private var realtimeLanguageCode = ""
  @AppStorage(AppDefaultsKey.realtimeSecondaryLanguages) private var rawSecondaryLanguages = ""
  @AppStorage(AppDefaultsKey.languageCodeVoxtral) private var voxtralLanguageCode = ""

  private var provider: TranscriptionProvider {
    TranscriptionProvider(rawValue: rawProvider) ?? .defaultProvider
  }

  var body: some View {
    SectionBoxWithTitle("Transcription", caption: caption) {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Provider", selection: $rawProvider) {
          ForEach(TranscriptionProvider.allCases) { provider in
            Text(provider.displayName).tag(provider.rawValue)
          }
        }

        if provider.languageCodeKey != nil {
          mainLanguagePicker
        }

        if provider.supportsSecondaryLanguages {
          secondaryLanguagesMenu
        }

        if provider.transcriptEditKey != nil {
          transcriptEditField
        }
      }
    }
  }

  private var caption: String {
    switch provider {
    case .scribeV2, .scribeV2Realtime:
      return "Transcript edit applies your instruction to each transcript (up to 2000 characters). It adds 30% to the transcription cost."
    case .voxtral:
      return "Uses your Mistral AI key. Up to 100 dictionary words guide the spelling of names and terms."
    case .voxtralRealtime:
      return "Uses your Mistral AI key. The language is detected automatically and dictionary words are not used."
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
    case .scribeV2Realtime, .voxtralRealtime:
      return $realtimeLanguageCode
    }
  }

  private var secondaryLanguagesMenu: some View {
    LabeledContent("Secondary languages") {
      Menu(secondaryLanguagesSummary) {
        ForEach(TranscriptionLanguages.codes.filter { $0 != realtimeLanguageCode }, id: \.self) { code in
          Toggle(TranscriptionLanguages.displayName(for: code), isOn: secondaryLanguageBinding(code))
        }
      }
      .fixedSize()
    }
  }

  private var secondaryLanguagesSummary: String {
    let names = TranscriptionLanguages.decode(rawSecondaryLanguages)
      .filter { $0 != realtimeLanguageCode }
      .map(TranscriptionLanguages.displayName(for:))
    return names.isEmpty ? "None" : names.joined(separator: ", ")
  }

  private func secondaryLanguageBinding(_ code: String) -> Binding<Bool> {
    Binding(
      get: { TranscriptionLanguages.decode(rawSecondaryLanguages).contains(code) },
      set: { isSelected in
        var codes = TranscriptionLanguages.decode(rawSecondaryLanguages).filter { $0 != code }
        if isSelected {
          codes.append(code)
        }
        rawSecondaryLanguages = TranscriptionLanguages.encode(codes)
      }
    )
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
      get: { provider == .scribeV2 ? scribeV2TranscriptEdit : realtimeTranscriptEdit },
      set: { newValue in
        let limited = String(newValue.prefix(TranscriptionSettings.transcriptEditMaxLength))
        if provider == .scribeV2 {
          scribeV2TranscriptEdit = limited
        } else {
          realtimeTranscriptEdit = limited
        }
      }
    )
  }
}
