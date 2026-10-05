import AppKit
import SwiftData
import SwiftUI


/// How dictated text gets into other apps: the insertion method, and context pasting (smart
/// paste) with how well it works in each app or website the user dictated into.
struct TextInsertionTabView: View {
  @Environment(\.openWindow) private var openWindow
  @AppStorage(AppDefaultsKey.textInsertionMethod) private var textInsertionMethod = TextInsertionMethod.default
  @AppStorage(AppDefaultsKey.smartPasteFormatting) private var smartPasteFormatting = true
  @AppStorage(AppDefaultsKey.smartPasteHints) private var smartPasteHints: Data?
  @AppStorage(AppDefaultsKey.dismissedSmartPasteHints) private var dismissedSmartPasteHints: Data?
  @Query(sort: \ContextPasteApp.lastPasteAt, order: .reverse) private var apps: [ContextPasteApp]

  private var activeHints: [SmartPasteHint] {
    SmartPasteHints.active(found: smartPasteHints, dismissed: dismissedSmartPasteHints)
  }

  var body: some View {
    VStack {
      SectionBoxWithTitle(
        "Match surrounding text",
        caption: "Reads what sits before the cursor through accessibility. Heuristic, so it gets abbreviations and quotes wrong sometimes."
      ) {
        ContextPasteAnimation()
        Divider()
        HStack {
          Toggle("Match surrounding text when pasting", isOn: $smartPasteFormatting)
          Spacer()
          Button("Inspect…") {
            openWindow(id: PasteContextInspectorView.windowID)
          }
          .help("See what accessibility exposes in other apps and what pasting would produce there.")
        }
        if smartPasteFormatting {
          ForEach(activeHints) { hint in
            SmartPasteHintRow(hint: hint) {
              SmartPasteHints.dismiss(hint, in: .standard)
            }
          }
        }
      }
      .animation(.easeInOut(duration: 0.2), value: activeHints)

      appsSection

      SectionBoxWithTitle("Method", caption: textInsertionMethod.explanation) {
        Picker("Insert text by", selection: $textInsertionMethod) {
          ForEach(TextInsertionMethod.allCases) { method in
            Text(method.title).tag(method)
          }
        }
      }
    }
    .padding([.bottom, .horizontal])
  }

  private var appsSection: some View {
    SectionBoxWithTitle(
      "Apps",
      caption: "Where you dictated with this on, and how much of the text around the cursor could be read there. Kept on this Mac only."
    ) {
      if apps.isEmpty {
        Text("Dictate into an app with this on, and it shows up here.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(apps) { app in
          ContextPasteAppRow(app: app)
          if app.id != apps.last?.id { Divider() }
        }
        HStack {
          Spacer()
          Button("Clear History") { ContextPasteHistory().clear() }
            .controlSize(.small)
        }
      }
    }
  }
}


private struct ContextPasteAppRow: View {
  let app: ContextPasteApp

  var body: some View {
    HStack(spacing: 10) {
      AppIcon(bundleIdentifier: app.bundleIdentifier)

      VStack(alignment: .leading, spacing: 1) {
        Text(app.website ?? app.appName)
        Text(details)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      QualityBadge(quality: app.lastQuality)
    }
  }

  private var details: String {
    var parts: [String] = []
    if app.website != nil { parts.append("in \(app.appName)") }
    let pastes = app.pasteCount == 1 ? "1 paste" : "\(app.pasteCount) pastes"
    parts.append(app.goodPastes == app.pasteCount ? pastes : "\(app.goodPastes) of \(pastes) fully read")
    parts.append(app.lastPasteAt.formatted(.relative(presentation: .named)))
    return parts.joined(separator: " · ")
  }
}


private struct QualityBadge: View {
  let quality: CursorContextReport.Quality

  var body: some View {
    Label(title, systemImage: icon)
      .font(.caption)
      .foregroundStyle(color)
      .help(explanation)
  }

  private var title: String {
    switch quality {
    case .good: "Reads context"
    case .partial: "Partial"
    case .none: "No context"
    }
  }

  private var icon: String {
    switch quality {
    case .good: "checkmark.circle.fill"
    case .partial: "circle.lefthalf.filled"
    case .none: "xmark.circle"
    }
  }

  private var color: Color {
    switch quality {
    case .good: .green
    case .partial: .orange
    case .none: .secondary
    }
  }

  private var explanation: String {
    switch quality {
    case .good: "The last paste here read the text before the cursor."
    case .partial: "The last paste here only read part of the text before the cursor, so spacing and capitals are partly guessed."
    case .none: "This app doesn't share the text around the cursor: the last paste here went in as dictated."
    }
  }
}


private struct AppIcon: View {
  let bundleIdentifier: String?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
      } else {
        Image(systemName: "app.dashed")
          .resizable()
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 22, height: 22)
  }

  private var image: NSImage? {
    bundleIdentifier
      .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
      .map { NSWorkspace.shared.icon(forFile: $0.path) }
  }
}


/// One ``SmartPasteHint``, with a button to dismiss it.
struct SmartPasteHintRow: View {
  let hint: SmartPasteHint
  let dismiss: () -> Void

  private var title: String {
    switch hint.kind {
    case .monacoScreenReaderMode: "Turn on screen reader mode in \(hint.place)"
    }
  }

  private var message: String {
    switch hint.kind {
    case .monacoScreenReaderMode:
      "The code editor there only shares the character before the cursor, so the surrounding text is partly guessed. Press ⌘⇧P and run \"Toggle Screen Reader Accessibility Mode\"."
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button(action: dismiss) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help("Don't show again")
    }
    .padding(10)
    .background(
      Color.orange.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
    )
  }
}
