import Foundation
import SwiftData
import Testing
@testable import L_Alfred


@MainActor
struct ContextPasteHistoryTests {
  private let container = try! LocalStore.makeContainer(inMemory: true)
  private let cursor = PastePlace(bundleIdentifier: "com.todesktop.230313mzl4w4u92", appName: "Cursor", website: nil)
  private let vscodeWeb = PastePlace(bundleIdentifier: "company.thebrowser.dia", appName: "Dia", website: "vscode.dev")
  private let gmail = PastePlace(bundleIdentifier: "company.thebrowser.dia", appName: "Dia", website: "mail.google.com")

  private var history: ContextPasteHistory { ContextPasteHistory(context: container.mainContext) }

  private func report(_ place: PastePlace, _ quality: CursorContextReport.Quality) -> CursorContextReport {
    CursorContextReport(context: nil, quality: quality, place: place)
  }

  private func apps() throws -> [ContextPasteApp] {
    try container.mainContext.fetch(FetchDescriptor<ContextPasteApp>(sortBy: [SortDescriptor(\.key)]))
  }

  @Test func countsPastesPerPlace() throws {
    history.record(report(cursor, .partial))
    history.record(report(cursor, .good))
    history.record(report(vscodeWeb, .partial))

    let byKey = Dictionary(uniqueKeysWithValues: try apps().map { ($0.key, $0) })
    let cursorApp = try #require(byKey[cursor.key])
    #expect(cursorApp.pasteCount == 2)
    #expect(cursorApp.goodPastes == 1)
    #expect(cursorApp.partialPastes == 1)
    #expect(cursorApp.lastQuality == .good)
    #expect(byKey[vscodeWeb.key]?.pasteCount == 1)
  }

  /// Two websites in the same browser are two entries.
  @Test func websitesAreSeparate() throws {
    history.record(report(vscodeWeb, .partial))
    history.record(report(gmail, .good))
    let count = try apps().count
    #expect(count == 2)
  }

  @Test func clearRemovesEverything() throws {
    history.record(report(cursor, .good))
    history.clear()
    let remaining = try apps()
    #expect(remaining.isEmpty)
  }

  @Test func placeNames() {
    #expect(cursor.displayName == "Cursor")
    #expect(vscodeWeb.displayName == "vscode.dev (Dia)")
    #expect(vscodeWeb.key == "company.thebrowser.dia|vscode.dev")
  }

  @Test func theLocalStoreIsInMemoryDuringTests() {
    let inMemory = LocalStore.container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
    #expect(inMemory)
  }
}


struct ContextQualityTests {
  private func resolution(method: CursorContextMethod?) -> CursorContextResolution {
    CursorContextResolution(rule: CursorContextRules.ordered.last!, method: method, reading: nil)
  }

  @Test func nothingReadMeansNone() {
    #expect(CursorContextReport.Quality.of(resolution(method: nil), isMonacoWithoutScreenReader: false) == .none)
  }

  @Test func monacoWithoutScreenReaderIsPartial() {
    #expect(CursorContextReport.Quality.of(resolution(method: .nativeValue), isMonacoWithoutScreenReader: true) == .partial)
  }

  @Test func aReadingIsGood() {
    #expect(CursorContextReport.Quality.of(resolution(method: .nativeValue), isMonacoWithoutScreenReader: false) == .good)
  }
}
