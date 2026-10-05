import Foundation
import Testing
@testable import L_Alfred


struct MonacoEditorTests {
  private func facts(_ classes: Set<String>) -> CursorElementFacts {
    CursorElementFacts(attributeNames: [], domClasses: classes, hasChildren: false)
  }

  /// Classes of Cursor's editor field, as captured with tools/axlab.
  @Test func recognizesMonacoInputArea() {
    #expect(MonacoEditor.isEditor(facts(["inputarea", "monaco-mouse-cursor-text"])))
  }

  /// VS Code online (vscode.dev in Dia), captured with the paste context inspector.
  @Test func recognizesEditContextField() {
    #expect(MonacoEditor.isEditor(facts(["native-edit-context"])))
  }

  @Test func ignoresOtherFields() {
    #expect(!MonacoEditor.isEditor(facts(["aislash-editor-input"])))
    #expect(!MonacoEditor.isEditor(facts(["inputarea"])))
    #expect(!MonacoEditor.isEditor(facts([])))
  }

  /// Without screen reader mode the field holds the character before the cursor, or nothing.
  @Test func singleCharacterMeansNoScreenReaderMode() {
    #expect(MonacoEditor.lacksScreenReaderMode(value: ";"))
    #expect(MonacoEditor.lacksScreenReaderMode(value: ""))
    #expect(MonacoEditor.lacksScreenReaderMode(value: nil))
  }

  /// With it, the field holds the lines around the cursor.
  @Test func linesMeanScreenReaderMode() {
    #expect(!MonacoEditor.lacksScreenReaderMode(value: "hey\nthere"))
  }
}
