import SwiftUI

/// A microphone of the priority list, dragged to reorder it.
struct MicrophonePriorityRow: View {
  let rank: Int
  let count: Int
  let name: String
  /// Nil when the microphone is not connected.
  let device: InputDevice?
  let isInUse: Bool
  let isDragged: Bool
  let move: (_ toIndex: Int) -> Void
  let remove: () -> Void
  @State private var isHovered = false

  private var index: Int { rank - 1 }
  private var isConnected: Bool { device != nil }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.tertiary)
      Text("\(rank)")
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 12)
      Image(systemName: Self.symbolName(for: device))
        .foregroundStyle(isConnected ? .primary : .tertiary)
        .frame(width: 22)
      nameAndState
      Spacer(minLength: 0)
      if isInUse {
        InUseBadge()
      }
      RowDeleteButton(helpText: "Forget this microphone", isVisible: !isConnected, action: remove)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background))
    .overlay(border)
    .opacity(isDragged ? 0.5 : 1)
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .help("Drag to change the order")
    .contextMenu { menu }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(rank). \(name)")
    .accessibilityAction(named: "Move up") { move(index - 1) }
    .accessibilityAction(named: "Move down") { move(index + 1) }
  }

  private var nameAndState: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(name)
        .foregroundStyle(isConnected ? .primary : .secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      if !isConnected {
        Text("Not connected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var border: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .strokeBorder(
        isDragged ? Color.accentColor : Color(nsColor: .separatorColor).opacity(isHovered ? 1 : 0.85),
        style: StrokeStyle(lineWidth: 1, dash: isDragged ? [4, 3] : [])
      )
  }

  @ViewBuilder
  private var menu: some View {
    Button("Move to Top") { move(0) }
      .disabled(index == 0)
    Button("Move Up") { move(index - 1) }
      .disabled(index == 0)
    Button("Move Down") { move(index + 1) }
      .disabled(index == count - 1)
    if !isConnected {
      Divider()
      RowDeleteMenuButton(title: "Forget this microphone", action: remove)
    }
  }

  static func symbolName(for device: InputDevice?) -> String {
    guard let device else { return "mic.slash" }
    switch device.transport {
    case .builtIn: return device.isInternalMic ? "laptopcomputer" : "headphones"
    case .bluetooth: return "headphones"
    case .virtual: return "waveform"
    case .other: return "mic"
    }
  }
}

/// Marks the microphone a dictation started now would record from.
struct InUseBadge: View {
  var body: some View {
    Text("In use")
      .font(.caption.weight(.medium))
      .foregroundStyle(Color.accentColor)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(Color.accentColor.opacity(0.15), in: Capsule())
      .help("A dictation started now records from this microphone")
  }
}
