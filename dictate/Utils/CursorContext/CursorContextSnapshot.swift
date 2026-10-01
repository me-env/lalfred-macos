import Foundation


/// Everything the accessibility API exposes about the focused element at one moment,
/// plus what each cursor-context strategy made of it.
///
/// Captured by ``CursorContextProbe`` for the paste context inspector. Saved snapshots are
/// plain JSON so they can be dropped into `dictateTests/PasteContextFixtures/` and replayed
/// against ``PasteTextTransformer`` (see `PasteContextFixtureTests`).
nonisolated struct CursorContextSnapshot: Codable, Sendable, Identifiable {
  var id = UUID()
  var capturedAt = Date()
  var app: AppInfo
  var element: ElementSummary
  /// One reading per ``CursorContextMethod``, keyed by its `displayName`.
  var strategies: [StrategyReading]
  /// Closest parent first.
  var ancestors: [ElementSummary]
  var attributes: [AttributeReading]
  var parameterizedAttributes: [String]
  var actions: [String]
  var tree: TreeNode?

  // Filled in by hand in the inspector before saving, to turn the snapshot into a fixture.
  var sampleText: String = ""
  var expectedResult: String?
  var note: String?

  struct AppInfo: Codable, Sendable, Hashable {
    var name: String?
    var bundleIdentifier: String?
    var pid: Int32
  }

  struct ElementSummary: Codable, Sendable, Hashable {
    var role: String?
    var subrole: String?
    var roleDescription: String?
    var identifier: String?
    var title: String?
    var description: String?
    var placeholder: String?
    var domIdentifier: String?
    var domClassList: [String]
    var numberOfCharacters: Int?
    var selectedRange: RangeInfo?

    var headline: String {
      [role, subrole].compactMap { $0 }.joined(separator: " / ")
    }
  }

  struct RangeInfo: Codable, Sendable, Hashable {
    var location: Int
    var length: Int
  }

  struct AttributeReading: Codable, Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var value: String
  }

  /// What one method read around the cursor.
  struct StrategyReading: Codable, Sendable, Hashable, Identifiable {
    var id: String { name }
    /// ``CursorContextMethod/displayName``.
    var name: String
    var summary: String
    /// Tail of the text before the cursor, `nil` when the method isn't supported here.
    var textBeforeCursor: String?
    /// Head of the text after the cursor, when the method can read it.
    var textAfterCursor: String?
  }

  struct TreeNode: Codable, Sendable, Hashable, Identifiable {
    /// Index path from the focused element, e.g. `0.2.1`.
    var id: String
    var role: String?
    var subrole: String?
    var valuePreview: String?
    var numberOfCharacters: Int?
    var selectedRange: RangeInfo?
    var domClassList: [String]
    /// `nil` for leaves, so the view can tell them apart from collapsed nodes.
    var children: [TreeNode]?
    /// Set when children were dropped because of depth / node limits.
    var isTruncated: Bool = false
  }
}


extension CursorContextSnapshot {
  func reading(for method: CursorContextMethod) -> CursorReading? {
    if let constantReading = method.constantReading { return constantReading }
    guard let stored = strategies.first(where: { $0.name == method.displayName }),
          let before = stored.textBeforeCursor else { return nil }
    return CursorReading(textBeforeCursor: before, textAfterCursor: stored.textAfterCursor)
  }

  /// Routes the snapshot through ``CursorContextRules`` exactly like pasting would.
  var resolution: CursorContextResolution {
    CursorContextResolution.resolve(facts: CursorElementFacts(snapshot: self)) { reading(for: $0) }
  }
}
