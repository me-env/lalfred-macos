import Foundation
import Testing
@testable import L_Alfred


/// Replays the snapshots in `PasteContextFixtures/` (saved from the paste context
/// inspector) through the routing rules and the transformer.
struct PasteContextFixtureTests {
  private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "PasteContextFixtures")

  private static func loadFixtures() throws -> [(name: String, snapshot: CursorContextSnapshot)] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let files = (try? FileManager.default.contentsOfDirectory(
      at: fixturesDirectory,
      includingPropertiesForKeys: nil
    )) ?? []
    return try files
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { url in
        (url.lastPathComponent, try decoder.decode(CursorContextSnapshot.self, from: Data(contentsOf: url)))
      }
  }

  /// Routes each snapshot through ``CursorContextRules`` (as pasting would, but from the
  /// saved data) and checks what pasting the sample text produces.
  @MainActor
  @Test func pasteMatchesExpectation() throws {
    for (name, snapshot) in try Self.loadFixtures() {
      guard let expected = snapshot.expectedResult else { continue }
      let resolution = snapshot.resolution
      let result = PasteTextTransformer.transform(snapshot.sampleText, context: resolution.context)
      #expect(
        result == expected,
        "\(name): rule '\(resolution.rule.name)' used \(resolution.method?.displayName ?? "nothing"). \(snapshot.note ?? "")"
      )
    }
  }
}
