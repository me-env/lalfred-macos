import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

struct MicrophoneSection: View {
  private static let listSpace = "microphonePriorityList"
  private let store = MicrophonePreferencesStore()
  /// Saved preferences plus the connected microphones not remembered yet; saved on the first edit.
  @State private var preferences = MicrophonePreferences()
  @State private var devices: [InputDevice] = []
  @State private var systemDefault: AudioDeviceID?
  @State private var isLidClosed = false
  /// The microphone being dragged, while the pointer is over the list.
  @State private var draggedUID: String?
  @State private var rowFrames: [String: CGRect] = [:]

  var body: some View {
    SectionBoxWithTitle("Microphone", caption: "A dictation keeps its microphone until it disconnects.") {
      Picker("Choose", selection: modeBinding) {
        Text("System default").tag(MicrophonePreferences.Mode.systemDefault)
        Text("Priority list").tag(MicrophonePreferences.Mode.priorityList)
      }
      .pickerStyle(.segmented)

      switch preferences.mode {
      case .systemDefault:
        systemDefaultSettings
      case .priorityList:
        priorityList
      }
    }
    .onAppear(perform: refresh)
    .onReceive(NotificationCenter.default.publisher(for: .audioDevicesDidChange)) { _ in refresh() }
  }

  /// The microphone a dictation started now would record from.
  private var microphoneInUse: InputDevice? {
    MicrophoneSelector.select(in: MicrophoneSelector.Context(
      devices: devices,
      systemDefault: systemDefault,
      preferences: preferences,
      isLidClosed: isLidClosed
    ))
  }

  private var systemDefaultSettings: some View {
    VStack(alignment: .leading, spacing: 8) {
      if hasInternalMic {
        bluetoothAvoidanceToggle
      }
      if let microphoneInUse {
        Label("Records from \(microphoneInUse.name)", systemImage: MicrophonePriorityRow.symbolName(for: microphoneInUse))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// A Mac mini or Studio has no microphone of its own to fall back on.
  private var hasInternalMic: Bool {
    devices.contains { $0.isInternalMic }
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
    let inUseUID = microphoneInUse?.uid
    return VStack(alignment: .leading, spacing: 6) {
      Text("Dictation records from the first connected microphone. Drag to reorder.")
        .font(.caption)
        .foregroundStyle(.secondary)
      VStack(spacing: 6) {
        ForEach(Array(preferences.priority.enumerated()), id: \.element.uid) { index, microphone in
          priorityRow(microphone, rank: index + 1, isInUse: microphone.uid == inUseUID)
        }
      }
      .coordinateSpace(.named(Self.listSpace))
      .onDrop(of: [.text], delegate: MicrophoneListDropDelegate(
        resume: { draggedUID = $0 },
        reorder: reorder(at:),
        end: { draggedUID = nil }
      ))
    }
  }

  private func priorityRow(
    _ microphone: MicrophonePreferences.RememberedMicrophone,
    rank: Int,
    isInUse: Bool
  ) -> some View {
    MicrophonePriorityRow(
      rank: rank,
      count: preferences.priority.count,
      name: microphone.name,
      device: devices.first { $0.uid == microphone.uid },
      isInUse: isInUse,
      isDragged: draggedUID == microphone.uid,
      move: { index in move(microphone.uid, to: index) },
      remove: { save(preferences.removing(uid: microphone.uid)) }
    )
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { frame in
      rowFrames[microphone.uid] = frame
    }
    .onDrag { startDragging(microphone.uid) }
  }

  private var modeBinding: Binding<MicrophonePreferences.Mode> {
    Binding(
      get: { preferences.mode },
      set: { mode in update { $0.mode = mode } }
    )
  }

  private func startDragging(_ uid: String) -> NSItemProvider {
    draggedUID = uid
    return NSItemProvider(object: uid as NSString)
  }

  private func reorder(at location: CGPoint) {
    guard let draggedUID,
          let destination = MicrophoneListReorder.destinationIndex(
            dragging: draggedUID,
            pointerY: location.y,
            order: preferences.priority.map(\.uid),
            frames: rowFrames
          ) else {
      return
    }
    move(draggedUID, to: destination)
  }

  private func move(_ uid: String, to index: Int) {
    withAnimation(.snappy(duration: 0.2)) {
      save(preferences.moving(uid: uid, toIndex: index))
    }
  }

  private func refresh() {
    InputDeviceListMonitor.start()
    devices = AudioDevices.inputDevices()
    systemDefault = AudioDevices.defaultInput()
    isLidClosed = ClamshellState.isLidClosed()
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

/// Reorders the priority list live while a microphone is dragged over it.
private struct MicrophoneListDropDelegate: DropDelegate {
  /// Called with the dragged microphone when the pointer comes back over the list.
  let resume: @MainActor (String) -> Void
  let reorder: (CGPoint) -> Void
  let end: () -> Void

  func dropEntered(info: DropInfo) {
    guard let provider = info.itemProviders(for: [.text]).first else { return }
    _ = provider.loadObject(ofClass: NSString.self) { uid, _ in
      guard let uid = uid as? NSString else { return }
      let draggedUID = uid as String
      Task { @MainActor in resume(draggedUID) }
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    reorder(info.location)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    end()
  }

  func performDrop(info: DropInfo) -> Bool {
    end()
    return true
  }
}
