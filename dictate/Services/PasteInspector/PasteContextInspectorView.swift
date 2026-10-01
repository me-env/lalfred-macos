import SwiftUI
import AppKit


/// Floating developer window for the "match surrounding text when pasting" feature.
///
/// Click into any text field in any app and the window shows what the accessibility API
/// exposes for it, what every cursor-context strategy reads, and what pasting the sample
/// text would produce. Snapshots can be saved as JSON fixtures for
/// `dictateTests/PasteContextFixtures/`.
struct PasteContextInspectorView: View {
  static let windowID = "pasteContextInspector"

  @State private var model = PasteContextInspectorModel()

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      content
    }
    .frame(minWidth: 520, minHeight: 480)
    .onAppear { model.start() }
    .onDisappear { model.stop() }
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 10) {
      Toggle("Live", isOn: $model.isLive)
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Follow the focused field of other apps. L'Alfred's own fields are ignored.")
      Button("Capture now", systemImage: "scope") { model.captureNow() }
      Spacer()
      if let statusMessage = model.statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Button("Copy report", systemImage: "doc.on.doc") { model.copyReport() }
        .disabled(model.snapshot == nil)
      Menu {
        Button("Save snapshot") { model.saveSnapshot() }
          .disabled(model.snapshot == nil)
        Button("Reveal snapshots folder") { model.revealSnapshotsFolder() }
      } label: {
        Label("Save", systemImage: "square.and.arrow.down")
      } primaryAction: {
        model.saveSnapshot()
      }
      .fixedSize()
      .disabled(model.snapshot == nil)
    }
    .labelStyle(.titleAndIcon)
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    if !model.isAccessibilityTrusted {
      ContentUnavailableView {
        Label("Accessibility access needed", systemImage: "lock.shield")
      } description: {
        Text("The inspector reads other apps through the accessibility API.")
      } actions: {
        Button("Grant access") { model.requestAccessibility() }
      }
    } else if let snapshot = model.snapshot {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ElementHeader(snapshot: snapshot)
          pastePreview(snapshot)
          fixtureSection
          rawDataSection(snapshot)
        }
        .padding(12)
      }
    } else {
      ContentUnavailableView(
        "Click into a text field",
        systemImage: "cursorarrow.rays",
        description: Text("Focus any editable field in another app. This window stays on top.")
      )
    }
  }

  private func pastePreview(_ snapshot: CursorContextSnapshot) -> some View {
    SectionBoxWithTitle(
      "Paste preview",
      caption: model.strategiesDisagree
        ? "Strategies disagree on the context here, worth a closer look."
        : nil
    ) {
      TextField("Sample text to paste", text: $model.sampleText)
      RoutingSummary(resolution: snapshot.resolution, result: model.productionResult)
      ForEach(CursorContextMethod.allCases, id: \.self) { method in
        Divider()
        MethodRow(
          method: method,
          reading: snapshot.reading(for: method),
          role: MethodRow.Role(method: method, resolution: snapshot.resolution),
          result: model.result(for: method)
        )
      }
    }
  }

  private var fixtureSection: some View {
    SectionBoxWithTitle(
      "Fixture",
      caption: "Fill in what pasting should produce, save, and copy the JSON into dictateTests/PasteContextFixtures/ to make it a regression test."
    ) {
      TextField(
        "Expected result",
        text: $model.expectedResult,
        prompt: Text(model.productionResult ?? "Expected result")
      )
      TextField("Note (optional)", text: $model.note)
      if !model.expectedResult.isEmpty, let productionResult = model.productionResult {
        let matches = productionResult == model.expectedResult
        Label(
          matches ? "Production matches the expectation" : "Production gives \(productionResult.debugDescription)",
          systemImage: matches ? "checkmark.circle.fill" : "xmark.octagon.fill"
        )
        .font(.caption)
        .foregroundStyle(matches ? .green : .red)
      }
    }
  }

  private func rawDataSection(_ snapshot: CursorContextSnapshot) -> some View {
    SectionBox {
      DisclosureGroup("Attributes (\(snapshot.attributes.count))") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(snapshot.attributes) { attribute in
            KeyValueRow(key: attribute.name, value: attribute.value)
          }
        }
        .padding(.top, 4)
      }
      Divider()
      DisclosureGroup("Parameterized attributes (\(snapshot.parameterizedAttributes.count))") {
        MonospacedList(items: snapshot.parameterizedAttributes)
      }
      Divider()
      DisclosureGroup("Actions (\(snapshot.actions.count))") {
        MonospacedList(items: snapshot.actions)
      }
      Divider()
      DisclosureGroup("Ancestors (\(snapshot.ancestors.count))") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(snapshot.ancestors.enumerated()), id: \.offset) { depth, ancestor in
            ElementLine(summary: ancestor)
              .padding(.leading, CGFloat(depth) * 10)
          }
        }
        .padding(.top, 4)
      }
      if let tree = snapshot.tree, tree.children != nil {
        Divider()
        DisclosureGroup("Children tree") {
          TreeNodeView(node: tree)
            .padding(.top, 4)
        }
      }
    }
  }
}


// MARK: - Subviews

private struct ElementHeader: View {
  let snapshot: CursorContextSnapshot

  var body: some View {
    SectionBox {
      HStack(alignment: .top, spacing: 10) {
        if let icon = NSRunningApplication(processIdentifier: snapshot.app.pid)?.icon {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 32, height: 32)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(snapshot.app.name ?? "Unknown app")
            .font(.headline)
          Text(snapshot.app.bundleIdentifier ?? "no bundle id")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        Spacer()
        Text(snapshot.resolution.rule.name)
          .font(.caption.monospaced())
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      VStack(alignment: .leading, spacing: 2) {
        KeyValueRow(key: "Role", value: snapshot.element.headline)
        optionalRow("Role description", snapshot.element.roleDescription)
        optionalRow("Identifier", snapshot.element.identifier)
        optionalRow("Description", snapshot.element.description)
        optionalRow("Placeholder", snapshot.element.placeholder)
        optionalRow("DOM id", snapshot.element.domIdentifier)
        if !snapshot.element.domClassList.isEmpty {
          KeyValueRow(key: "DOM classes", value: snapshot.element.domClassList.joined(separator: " "))
        }
        if let range = snapshot.element.selectedRange {
          KeyValueRow(key: "Selection", value: "location \(range.location), length \(range.length)")
        }
        optionalRow("Characters", snapshot.element.numberOfCharacters.map(String.init))
      }
      .padding(.top, 6)
    }
  }

  @ViewBuilder
  private func optionalRow(_ key: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
      KeyValueRow(key: key, value: value)
    }
  }
}

/// Which rule matched, what it tries, and what pasting produces.
private struct RoutingSummary: View {
  let resolution: CursorContextResolution
  let result: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Rule: \(resolution.rule.name)")
        .font(.subheadline.weight(.semibold))
      Text(resolution.rule.evidence)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Tries: " + (resolution.rule.methods.isEmpty
        ? "nothing, pastes unchanged"
        : resolution.rule.methods.map(\.displayName).joined(separator: " → ")))
        .font(.caption)
      if let result {
        Text("Pasting gives \(result.debugDescription)\(resolution.method == nil ? " (unchanged, no method could read)" : "")")
          .font(.callout.monospaced())
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct MethodRow: View {
  /// Where the method stands in the matched rule.
  enum Role {
    case used, fallback, unused

    init(method: CursorContextMethod, resolution: CursorContextResolution) {
      if method == resolution.method { self = .used }
      else if resolution.rule.methods.contains(method) { self = .fallback }
      else { self = .unused }
    }
  }

  let method: CursorContextMethod
  let reading: CursorReading?
  let role: Role
  let result: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(method.displayName)
          .font(.subheadline.weight(.semibold))
        switch role {
        case .used: Badge(text: "USED WHEN PASTING", color: .accentColor)
        case .fallback: Badge(text: "FALLBACK", color: .gray)
        case .unused: EmptyView()
        }
        Spacer()
      }
      Text(method.summary)
        .font(.caption)
        .foregroundStyle(.secondary)

      if let reading {
        let context = reading.context
        CursorTextView(before: reading.textBeforeCursor, after: reading.textAfterCursor)
        HStack(spacing: 12) {
          ContextChip(label: "prev", value: context.previousCharacter.map(String.init))
          ContextChip(label: "prev non-ws", value: context.previousNonWhitespaceCharacter.map(String.init))
          ContextChip(label: "line break", value: context.hasLineBreakBeforeCursor ? "yes" : "no")
        }
        if let result {
          Text("→ \(result.debugDescription)")
            .font(.callout.monospaced())
            .textSelection(.enabled)
        }
      } else {
        Text("Not supported by this element")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct Badge: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption2.weight(.bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(color, in: Capsule())
  }
}

/// Text around the cursor with invisible characters made visible and the cursor marked.
private struct CursorTextView: View {
  let before: String
  let after: String?

  var body: some View {
    Text(attributed)
      .font(.caption.monospaced())
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
  }

  private var attributed: AttributedString {
    var prefix = AttributedString(Self.visible(String(before.suffix(240))))
    var cursor = AttributedString("▏")
    cursor.foregroundColor = .red
    cursor.font = .caption.monospaced().bold()
    var suffix = AttributedString(Self.visible(String((after ?? "").prefix(80))))
    suffix.foregroundColor = .secondary
    prefix.append(cursor)
    prefix.append(suffix)
    return prefix
  }

  private static func visible(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\n", with: "↵\n")
      .replacingOccurrences(of: "\t", with: "⇥")
      .replacingOccurrences(of: "\u{00A0}", with: "⍽")
  }
}

private struct ContextChip: View {
  let label: String
  let value: String?

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value.map(\.debugDescription) ?? "nil")
        .monospaced()
    }
    .font(.caption)
  }
}

private struct KeyValueRow: View {
  let key: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(key)
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)
      Text(value)
        .monospaced()
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption)
  }
}

private struct MonospacedList: View {
  let items: [String]

  var body: some View {
    Text(items.isEmpty ? "none" : items.joined(separator: "\n"))
      .font(.caption.monospaced())
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)
  }
}

private struct ElementLine: View {
  let summary: CursorContextSnapshot.ElementSummary

  var body: some View {
    let details = [
      summary.identifier.map { "#\($0)" },
      summary.domClassList.isEmpty ? nil : "." + summary.domClassList.joined(separator: "."),
      summary.description.flatMap { $0.isEmpty ? nil : "\"\($0)\"" },
    ].compactMap { $0 }.joined(separator: " ")
    Text("\(summary.headline) \(details)")
      .font(.caption.monospaced())
      .lineLimit(1)
      .truncationMode(.tail)
      .textSelection(.enabled)
  }
}

private struct TreeNodeView: View {
  let node: CursorContextSnapshot.TreeNode
  @State private var isExpanded = true

  var body: some View {
    if let children = node.children {
      DisclosureGroup(isExpanded: $isExpanded) {
        ForEach(children) { TreeNodeView(node: $0) }
        if node.isTruncated { truncatedNote }
      } label: {
        label
      }
    } else {
      HStack(spacing: 0) {
        label
        if node.isTruncated { truncatedNote }
      }
      .padding(.leading, 18)
    }
  }

  private var label: some View {
    var parts = [[node.role, node.subrole].compactMap { $0 }.joined(separator: "/")]
    if let count = node.numberOfCharacters { parts.append("chars=\(count)") }
    if let range = node.selectedRange { parts.append("sel=\(range.location)+\(range.length)") }
    if !node.domClassList.isEmpty { parts.append("." + node.domClassList.joined(separator: ".")) }
    if let value = node.valuePreview, !value.isEmpty { parts.append(value.debugDescription) }
    return Text(parts.joined(separator: "  "))
      .font(.caption.monospaced())
      .lineLimit(1)
      .truncationMode(.tail)
      .textSelection(.enabled)
  }

  private var truncatedNote: some View {
    Text(" … more children not loaded")
      .font(.caption)
      .foregroundStyle(.tertiary)
  }
}
