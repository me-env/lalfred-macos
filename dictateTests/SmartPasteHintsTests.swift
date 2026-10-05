import Foundation
import Testing
@testable import L_Alfred


struct SmartPasteHintsTests {
  private let defaults = UserDefaults(suiteName: "SmartPasteHintsTests.\(UUID().uuidString)")!
  private let cursor = SmartPasteHint(kind: .monacoScreenReaderMode, place: "Cursor")
  private let vscodeWeb = SmartPasteHint(kind: .monacoScreenReaderMode, place: "vscode.dev (Dia)")

  @Test func keepsOneHintPerPlace() {
    SmartPasteHints.note(cursor, in: defaults)
    SmartPasteHints.note(vscodeWeb, in: defaults)
    SmartPasteHints.note(cursor, in: defaults)
    #expect(SmartPasteHints.active(in: defaults) == [cursor, vscodeWeb])
  }

  @Test func dismissingHidesOnlyThatPlace() {
    SmartPasteHints.note(cursor, in: defaults)
    SmartPasteHints.note(vscodeWeb, in: defaults)
    SmartPasteHints.dismiss(cursor, in: defaults)
    #expect(SmartPasteHints.active(in: defaults) == [vscodeWeb])
  }

  @Test func dismissedStaysHiddenWhenFoundAgain() {
    SmartPasteHints.note(cursor, in: defaults)
    SmartPasteHints.dismiss(cursor, in: defaults)
    SmartPasteHints.resolve(cursor, in: defaults)
    SmartPasteHints.note(cursor, in: defaults)
    #expect(SmartPasteHints.active(in: defaults).isEmpty)
  }

  @Test func resolvingRemovesTheHint() {
    SmartPasteHints.note(cursor, in: defaults)
    SmartPasteHints.resolve(cursor, in: defaults)
    #expect(SmartPasteHints.active(in: defaults).isEmpty)
  }
}
