import SwiftUI

struct MicrophoneSection: View {
  private let store = MicrophonePreferencesStore()
  /// Saved preferences plus the connected microphones not remembered yet; saved on the first edit.
  @State private var preferences = MicrophonePreferences()
  @State private var connectedUIDs: Set<String> = []

  var body: some View {
    SectionBoxWithTitle("Microphone", caption: "A dictation keeps its microphone until it disconnects.") {
      Picker("Choose", selection: modeBinding) {
        Text("System default").tag(MicrophonePreferences.Mode.systemDefault)
        Text("Priority list").tag(MicrophonePreferences.Mode.priorityList)
      }
      .pickerStyle(.segmented)

      switch preferences.mode {
      case .systemDefault:
        bluetoothAvoidanceToggle
      case .priorityList:
        priorityList
      }
    }
    .onAppear(perform: refresh)
    .onReceive(NotificationCenter.default.publisher(for: .audioDevicesDidChange)) { _ in refresh() }
  }

  private var bluetoothAvoidanceToggle: some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle("Use the Mac's microphone instead of Bluetooth headphones", isOn: Binding(
        get: { preferences.avoidBluetoothMicrophone },
        set: { isOn in update { $0.avoidBluetoothMicrophone = isOn } }
      ))
      Text("Keeps headphones in high quality audio while you dictate.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var priorityList: some View {
    VStack(spacing: 6) {
      ForEach(Array(preferences.priority.enumerated()), id: \.element.uid) { index, microphone in
        MicrophonePriorityRow(
          name: microphone.name,
          isConnected: connectedUIDs.contains(microphone.uid),
          canMoveUp: index > 0,
          canMoveDown: index < preferences.priority.count - 1,
          move: { offset in save(preferences.moving(uid: microphone.uid, by: offset)) },
          remove: { save(preferences.removing(uid: microphone.uid)) }
        )
      }
    }
  }

  private var modeBinding: Binding<MicrophonePreferences.Mode> {
    Binding(
      get: { preferences.mode },
      set: { mode in update { $0.mode = mode } }
    )
  }

  private func refresh() {
    InputDeviceListMonitor.start()
    let devices = AudioDevices.inputDevices()
    connectedUIDs = Set(devices.map(\.uid))
    preferences = store.load().remembering(devices)
  }

  private func update(_ change: (inout MicrophonePreferences) -> Void) {
    var updated = preferences
    change(&updated)
    save(updated)
  }

  private func save(_ updated: MicrophonePreferences) {
    preferences = updated
    store.save(updated)
  }
}

private struct MicrophonePriorityRow: View {
  let name: String
  let isConnected: Bool
  let canMoveUp: Bool
  let canMoveDown: Bool
  let move: (Int) -> Void
  let remove: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 0) {
        Text(name)
        if !isConnected {
          Text("Not connected")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button { move(-1) } label: { Image(systemName: "chevron.up") }
        .disabled(!canMoveUp)
        .help("Prefer this microphone")
      Button { move(1) } label: { Image(systemName: "chevron.down") }
        .disabled(!canMoveDown)
        .help("Prefer other microphones")
      RowDeleteButton(helpText: "Forget this microphone", isVisible: !isConnected, action: remove)
    }
    .buttonStyle(.borderless)
  }
}
