//
//  Settings tab that lets the user pick which (if any) sound effect plays
//  when recording starts and stops. Mirrors the ModesTabView / SectionBox
//  patterns used elsewhere.
//

import SwiftUI
import AppKit

struct SoundsTabView: View {
  @AppStorage(AppDefaultsKey.soundEffectKind) private var rawKind: String = SoundEffectKind.defaultKind.rawValue

  private var selectedKind: SoundEffectKind {
    SoundEffectKind(rawValue: rawKind) ?? .defaultKind
  }

  var body: some View {
    VStack(spacing: 12) {
      SectionBoxWithTitle(
        "Sounds",
        caption: "Plays a discreet cue when recording starts and stops. All cues are short (under 200 ms) and capped at a polite volume."
      ) {
        let options = SoundEffectKind.allCases
        ForEach(Array(options.enumerated()), id: \.element.id) { index, kind in
          SoundOptionRow(
            kind: kind,
            isSelected: kind == selectedKind,
            onSelect: { selectKind(kind) }
          )

          if index < options.count - 1 {
            Divider()
          }
        }
      }
    }
    .padding()
  }

  private func selectKind(_ kind: SoundEffectKind) {
    guard kind.rawValue != rawKind else { return }
    rawKind = kind.rawValue
    // Notify listeners (player drops its cache, etc.).
    NotificationCenter.default.post(name: .soundEffectKindDidChange, object: nil)
  }
}

private struct SoundOptionRow: View {
  let kind: SoundEffectKind
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Radio-style indicator
      Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(kind.displayName)
            .font(.headline)
          if kind == .defaultKind {
            Text("Default")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                Capsule().fill(.secondary.opacity(0.15))
              )
          }
        }
        Text(kind.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      if kind != .none {
        HStack(spacing: 6) {
          Button {
            SoundEffectPlayer.shared.previewStart(of: kind)
          } label: {
            Label("Start", systemImage: "play.fill")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button {
            SoundEffectPlayer.shared.previewStop(of: kind)
          } label: {
            Label("Stop", systemImage: "stop.fill")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel("\(kind.displayName). \(kind.detail)")
  }
}

#Preview {
  SoundsTabView()
    .frame(width: 760, height: 460)
}
