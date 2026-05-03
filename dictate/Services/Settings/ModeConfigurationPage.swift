import SwiftUI

struct ModeConfigurationPage: View {
    let mode: ModeDefinition
    @ObservedObject var modeCatalog: ModeCatalog
    @Binding var activeShortcutEditorID: String?
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onBack) {
                Label("All Modes", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            ScrollView {
                ModeConfigurationEditor(
                    mode: mode,
                    modeCatalog: modeCatalog,
                    activeShortcutEditorID: $activeShortcutEditorID
                )
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ModeConfigurationEditor: View {
    let mode: ModeDefinition
    @ObservedObject var modeCatalog: ModeCatalog
    @Binding var activeShortcutEditorID: String?

    @State private var selectedPromptPresetID: String = ""
    @State private var useCustomPrompt: Bool = false
    @State private var customPromptText: String = ""

    init(mode: ModeDefinition, modeCatalog: ModeCatalog, activeShortcutEditorID: Binding<String?>) {
        self.mode = mode
        self.modeCatalog = modeCatalog
        _activeShortcutEditorID = activeShortcutEditorID

        let selection = modeCatalog.promptSelection(for: mode.id)
        switch selection {
        case let .preset(presetID):
            _selectedPromptPresetID = State(initialValue: presetID)
            _useCustomPrompt = State(initialValue: false)
            _customPromptText = State(initialValue: modeCatalog.resolvedPromptInstruction(for: mode.id) ?? "")
        case let .custom(prompt):
            _selectedPromptPresetID = State(initialValue: "default-default")
            _useCustomPrompt = State(initialValue: true)
            _customPromptText = State(initialValue: prompt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeDetailHeader(mode: mode)

            ModeShortcutCard(
                mode: mode,
                activeShortcutEditorID: $activeShortcutEditorID
            )

            ModePromptSettingsCard(
                mode: mode,
                modeCatalog: modeCatalog,
                selectedPromptPresetID: $selectedPromptPresetID,
                useCustomPrompt: $useCustomPrompt,
                onRestoreDefault: restoreModeDefaultPrompt,
                disableRestoreDefault: isUsingPromptModeDefault
            )

            ModePromptContentCard(
                mode: mode,
                modeCatalog: modeCatalog,
                useCustomPrompt: $useCustomPrompt,
                customPromptText: $customPromptText
            )
        }
        .onChange(of: selectedPromptPresetID) { _, newPresetID in
            guard !useCustomPrompt else { return }
            modeCatalog.selectPromptPreset(for: mode.id, presetID: newPresetID)
        }
        .onChange(of: useCustomPrompt) { _, useCustomPrompt in
            if useCustomPrompt {
                if customPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customPromptText = modeCatalog.resolvedPromptInstruction(for: mode.id) ?? ""
                }
                modeCatalog.saveCustomPrompt(for: mode.id, prompt: customPromptText)
            } else {
                modeCatalog.selectPromptPreset(for: mode.id, presetID: selectedPromptPresetID)
            }
        }
        .onChange(of: customPromptText) { _, newPrompt in
            guard useCustomPrompt else { return }
            modeCatalog.saveCustomPrompt(for: mode.id, prompt: newPrompt)
        }
    }

    private var isUsingPromptModeDefault: Bool {
        switch modeCatalog.promptSelection(for: mode.id) {
        case let .preset(presetID):
            return !useCustomPrompt && presetID == "default-default"
        case .custom:
            return false
        }
    }

    private func restoreModeDefaultPrompt() {
        modeCatalog.resetPromptToModeDefault(for: mode.id)
        selectedPromptPresetID = "default-default"
        useCustomPrompt = false
        customPromptText = modeCatalog.resolvedPromptInstruction(for: mode.id) ?? ""
    }
}

private struct ModeDetailHeader: View {
    let mode: ModeDefinition

    var body: some View {
        SectionBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(mode.title)
                        .font(.title3.weight(.semibold))

                    Text("Mode")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.secondary.opacity(0.14)))
                }

                Text("Tune how this mode is triggered and how its prompt post-processes transcript output.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModeShortcutCard: View {
    let mode: ModeDefinition
    @Binding var activeShortcutEditorID: String?

    var body: some View {
        SectionBoxWithTitle(
            "Shortcut",
            caption: "Used to start dictation directly in this mode."
        ) {
            ShortcutInput(
                label: "Trigger Shortcut",
                storeKey: mode.shortcutStoreKey,
                defaultShortcut: mode.defaultShortcut,
                activeShortcutEditorID: $activeShortcutEditorID
            )
        }
    }
}

private struct ModePromptSettingsCard: View {
    let mode: ModeDefinition
    @ObservedObject var modeCatalog: ModeCatalog
    @Binding var selectedPromptPresetID: String
    @Binding var useCustomPrompt: Bool
    let onRestoreDefault: () -> Void
    let disableRestoreDefault: Bool

    var body: some View {
        SectionBoxWithTitle(
            "Prompt Strategy",
            caption: "Choose a preset or enable a mode-specific custom prompt."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Preset")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 54, alignment: .leading)

                    Picker("Prompt", selection: $selectedPromptPresetID) {
                        ForEach(modeCatalog.listPromptPresets(for: mode.id)) { preset in
                            Text(preset.title).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer(minLength: 8)

                    Toggle("Custom Prompt", isOn: $useCustomPrompt)
                        .toggleStyle(.switch)
                        .fixedSize()
                }

                HStack {
                    Spacer()
                    Button("Restore Default") {
                        onRestoreDefault()
                    }
                    .disabled(disableRestoreDefault)
                }
            }
        }
    }
}

private struct ModePromptContentCard: View {
    let mode: ModeDefinition
    @ObservedObject var modeCatalog: ModeCatalog
    @Binding var useCustomPrompt: Bool
    @Binding var customPromptText: String

    private var resolvedPrompt: String? {
        modeCatalog.resolvedPromptInstruction(for: mode.id)
    }

    var body: some View {
        SectionBoxWithTitle(
            useCustomPrompt ? "Custom Prompt" : "Resolved Prompt",
            caption: useCustomPrompt
                ? "This text is persisted for this mode and will override the selected preset."
                : "Preview of the effective instruction sent for post-processing."
        ) {
            if useCustomPrompt {
                TextEditor(text: $customPromptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator.opacity(0.35), lineWidth: 1)
                    )
            } else if let prompt = resolvedPrompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator.opacity(0.25), lineWidth: 1)
                    )
            } else {
                Text("No LLM post-processing prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }
}
