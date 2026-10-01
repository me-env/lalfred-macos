import AppKit
import ApplicationServices
import Foundation


/// Reads the focused element with every ``CursorContextMethod`` and dumps the raw
/// accessibility data, so the paste context inspector can show what each app exposes.
/// Routing is not decided here: it's recomputed from the snapshot (`resolution`).
struct CursorContextProbe {
  /// Characters kept before / after the cursor in a reading.
  var lookback = 500
  var lookahead = 120
  var maxAncestors = 12
  var maxTreeDepth = 6
  var maxTreeNodes = 300
  var maxAttributeValueLength = 400

  /// Cheap identity of "where the cursor is", used to skip full captures while nothing moves.
  struct Fingerprint: Equatable {
    var pid: pid_t
    var elementHash: CFHashCode
    var selectedRange: CursorContextSnapshot.RangeInfo?
    var numberOfCharacters: Int?
  }

  func fingerprint() -> Fingerprint? {
    guard let element = AXAttr.copyFocusedElement() else { return nil }
    return Fingerprint(
      pid: pid(of: element),
      elementHash: CFHash(element),
      selectedRange: AXAttr.selectedRange(in: element).map(rangeInfo),
      numberOfCharacters: AXAttr.int(kAXNumberOfCharactersAttribute, in: element)
    )
  }

  func capture() -> CursorContextSnapshot? {
    guard let element = AXAttr.copyFocusedElement() else { return nil }

    let pid = pid(of: element)
    let runningApp = NSRunningApplication(processIdentifier: pid)
    var nodeBudget = maxTreeNodes
    return CursorContextSnapshot(
      app: .init(
        name: runningApp?.localizedName,
        bundleIdentifier: runningApp?.bundleIdentifier,
        pid: pid
      ),
      element: summary(of: element),
      strategies: CursorContextMethod.allCases.map { reading(of: element, with: $0) },
      ancestors: ancestors(of: element),
      attributes: attributes(of: element),
      parameterizedAttributes: AXAttr.parameterizedAttributeNames(in: element).sorted(),
      actions: (AXAttr.stringArray(AXUIElementCopyActionNames, in: element) ?? []).sorted(),
      tree: treeNode(for: element, path: "root", depth: 0, budget: &nodeBudget)
    )
  }

  // MARK: - Readings

  private func reading(
    of element: AXUIElement,
    with method: CursorContextMethod
  ) -> CursorContextSnapshot.StrategyReading {
    let reading = method.read(element)
    return .init(
      name: method.displayName,
      summary: method.summary,
      textBeforeCursor: reading.map { String($0.textBeforeCursor.suffix(lookback)) },
      textAfterCursor: reading?.textAfterCursor.map { String($0.prefix(lookahead)) }
    )
  }

  // MARK: - Raw accessibility data

  private func summary(of element: AXUIElement) -> CursorContextSnapshot.ElementSummary {
    .init(
      role: AXAttr.string(kAXRoleAttribute, in: element),
      subrole: AXAttr.string(kAXSubroleAttribute, in: element),
      roleDescription: AXAttr.string(kAXRoleDescriptionAttribute, in: element),
      identifier: AXAttr.string(kAXIdentifierAttribute, in: element),
      title: AXAttr.string(kAXTitleAttribute, in: element),
      description: AXAttr.string(kAXDescriptionAttribute, in: element),
      placeholder: AXAttr.string(kAXPlaceholderValueAttribute, in: element),
      domIdentifier: AXAttr.string("AXDOMIdentifier", in: element),
      domClassList: AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? [],
      numberOfCharacters: AXAttr.int(kAXNumberOfCharactersAttribute, in: element),
      selectedRange: AXAttr.selectedRange(in: element).map(rangeInfo)
    )
  }

  private func ancestors(of element: AXUIElement) -> [CursorContextSnapshot.ElementSummary] {
    var result: [CursorContextSnapshot.ElementSummary] = []
    var current = AXAttr.getParent(in: element)
    while let parent = current, result.count < maxAncestors {
      result.append(summary(of: parent))
      current = AXAttr.getParent(in: parent)
    }
    return result
  }

  private func attributes(of element: AXUIElement) -> [CursorContextSnapshot.AttributeReading] {
    AXAttr.attributeNames(in: element).sorted().map { name in
      var ref: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
      let value = error == .success
        ? AXAttr.debugDescription(for: ref)
        : "<unavailable: \(error.rawValue)>"
      return .init(name: name, value: truncated(value, to: maxAttributeValueLength))
    }
  }

  private func treeNode(
    for element: AXUIElement,
    path: String,
    depth: Int,
    budget: inout Int
  ) -> CursorContextSnapshot.TreeNode {
    budget -= 1
    let children = AXAttr.getChildren(in: element) ?? []
    var node = CursorContextSnapshot.TreeNode(
      id: path,
      role: AXAttr.string(kAXRoleAttribute, in: element),
      subrole: AXAttr.string(kAXSubroleAttribute, in: element),
      valuePreview: AXAttr.string(kAXValueAttribute, in: element).map { truncated($0, to: 120) },
      numberOfCharacters: AXAttr.int(kAXNumberOfCharactersAttribute, in: element),
      selectedRange: AXAttr.selectedRange(in: element).map(rangeInfo),
      domClassList: AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? []
    )
    guard !children.isEmpty else { return node }
    guard depth < maxTreeDepth, budget > 0 else {
      node.isTruncated = true
      return node
    }

    var childNodes: [CursorContextSnapshot.TreeNode] = []
    for (index, child) in children.enumerated() {
      guard budget > 0 else {
        node.isTruncated = true
        break
      }
      childNodes.append(treeNode(for: child, path: "\(path).\(index)", depth: depth + 1, budget: &budget))
    }
    node.children = childNodes
    return node
  }

  // MARK: - Helpers

  private func pid(of element: AXUIElement) -> pid_t {
    var pid: pid_t = -1
    AXUIElementGetPid(element, &pid)
    return pid
  }

  private func rangeInfo(_ range: CFRange) -> CursorContextSnapshot.RangeInfo {
    .init(location: range.location, length: range.length)
  }

  private func truncated(_ string: String, to limit: Int) -> String {
    guard string.count > limit else { return string }
    return string.prefix(limit) + "… (\(string.count) chars)"
  }
}
