import Foundation


/// Monaco, the code editor of VS Code, Cursor and many websites (vscode.dev, github.dev). It
/// draws its text itself and hides it from accessibility: the focused field is a hidden one
/// it takes keystrokes in. Without "screen reader optimized mode", that field only holds the
/// character before the cursor (or what was typed since the cursor last moved), so the
/// reading is partial. With it, the field holds the lines around the cursor.
enum MonacoEditor {
  /// Cursor's hidden field is a textarea (`inputarea`). Newer VS Code, at least on the web,
  /// takes keystrokes through an EditContext element instead (`native-edit-context`).
  static func isEditor(_ facts: CursorElementFacts) -> Bool {
    let classes = facts.domClasses
    return (classes.contains("inputarea") && classes.contains("monaco-mouse-cursor-text"))
      || classes.contains("native-edit-context")
  }

  /// Without screen reader mode the field never holds a line break. The field's description
  /// says so too, but VS Code translates it. A one-line file with the mode on looks the same,
  /// so this is a hint, not proof.
  static func lacksScreenReaderMode(value: String?) -> Bool {
    !(value ?? "").contains(where: \.isNewline)
  }
}
