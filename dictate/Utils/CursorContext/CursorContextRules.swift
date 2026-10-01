import ApplicationServices
import Foundation


/// The plain data routing rules look at. Built from the live focused element when pasting,
/// or from a saved ``CursorContextSnapshot`` in the inspector and fixture tests, so both
/// go through exactly the same rules.
struct CursorElementFacts: Equatable {
  var attributeNames: Set<String>
  var domClasses: Set<String>
  var hasChildren: Bool
}


/// A condition on ``CursorElementFacts``. Combine with `.all` / `.any` / `.not`.
///
/// Adding a pattern: add a case and its line in `matches`. If it needs data the facts
/// don't carry yet, add a field to ``CursorElementFacts`` and fill it in both builders.
indirect enum ElementPattern {
  case always
  case hasAttribute(String)
  case hasDOMClass(String)
  case hasChildren
  case not(ElementPattern)
  case all([ElementPattern])
  case any([ElementPattern])

  func matches(_ facts: CursorElementFacts) -> Bool {
    switch self {
    case .always: true
    case .hasAttribute(let name): facts.attributeNames.contains(name)
    case .hasDOMClass(let name): facts.domClasses.contains(name)
    case .hasChildren: facts.hasChildren
    case .not(let pattern): !pattern.matches(facts)
    case .all(let patterns): patterns.allSatisfy { $0.matches(facts) }
    case .any(let patterns): patterns.contains { $0.matches(facts) }
    }
  }
}


/// "When the element looks like this, read it with these methods, in this order."
struct CursorContextRule {
  let name: String
  let when: ElementPattern
  /// Tried in order; the first one that can read the element wins. If none can, the
  /// text is pasted unchanged. An empty list means "always paste unchanged".
  let methods: [CursorContextMethod]
  /// Why the rule exists, ideally naming the fixtures that prove it.
  let evidence: String
}


/// Which method reads which kind of element.
///
/// Rules are checked top to bottom and the first match wins, so put specific rules
/// before general ones. The last rule matches everything.
enum CursorContextRules {
  static let ordered: [CursorContextRule] = [
    CursorContextRule(
      name: "Empty Quill editor",
      when: .hasDOMClass("ql-blank"),
      methods: [.emptyField],
      evidence: "Chromium exposes Quill's CSS placeholder as AXValue (dia-quill-case1)."
    ),
    CursorContextRule(
      name: "Chromium rich text editor",
      when: .all([.hasAttribute("ChromeAXNodeId"), .hasChildren]),
      methods: [.textMarkerParagraphs, .childrenTreeWalk, .nativeValue],
      evidence: """
        Chromium's AXSelectedTextRange skips paragraph breaks, so the native offset drifts \
        one per paragraph (dia-*-case7/8, LinkedIn). Paragraph markers read it right and stay \
        under 1 ms in a 1,100-node Outlook thread, where the tree walk took 330 ms and \
        misread tables. Inputs and textareas have no children and stay native (dia-textarea).
        """
    ),
    CursorContextRule(
      name: "No character cursor",
      when: .not(.hasAttribute(kAXSelectedTextRangeAttribute)),
      methods: [.textMarkerParagraphs, .textMarkerSelection],
      evidence: """
        WebKit web areas like Mail's compose body only expose text markers (mail-case1…11). \
        Text marker selection reads from the document start, so it's only the fallback.
        """
    ),
    CursorContextRule(
      name: "Default",
      when: .always,
      methods: [.nativeValue],
      evidence: "Correct in TextEdit, Pages, Word, Xcode, and every Safari editor tested."
    ),
  ]

  static func rule(for facts: CursorElementFacts) -> CursorContextRule {
    // The last rule matches `.always`, so this never falls through.
    ordered.first { $0.when.matches(facts) } ?? ordered[ordered.count - 1]
  }
}


/// The outcome of routing one element: the rule that matched, and which of its methods
/// produced the reading (`nil` = paste unchanged).
struct CursorContextResolution {
  let rule: CursorContextRule
  let method: CursorContextMethod?
  let reading: CursorReading?

  var context: CursorTextContext? { reading?.context }

  /// Routes `facts` and asks `read` for each of the rule's methods until one answers.
  /// `read` is a live AX read when pasting, or a lookup into a saved snapshot.
  static func resolve(
    facts: CursorElementFacts,
    read: (CursorContextMethod) -> CursorReading?
  ) -> CursorContextResolution {
    let rule = CursorContextRules.rule(for: facts)
    for method in rule.methods {
      if let reading = read(method) {
        return CursorContextResolution(rule: rule, method: method, reading: reading)
      }
    }
    return CursorContextResolution(rule: rule, method: nil, reading: nil)
  }
}


extension CursorElementFacts {
  /// Facts of a live element.
  init(element: AXUIElement) {
    self.init(
      attributeNames: AXAttr.attributeNames(in: element),
      domClasses: Set(AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? []),
      hasChildren: !(AXAttr.getChildren(in: element) ?? []).isEmpty
    )
  }

  /// Facts of a saved snapshot.
  init(snapshot: CursorContextSnapshot) {
    self.init(
      attributeNames: Set(snapshot.attributes.map(\.name)),
      domClasses: Set(snapshot.element.domClassList),
      hasChildren: !(snapshot.tree?.children ?? []).isEmpty
    )
  }
}
