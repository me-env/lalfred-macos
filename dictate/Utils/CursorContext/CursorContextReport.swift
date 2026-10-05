import Foundation


/// What reading the context of one paste found, for the Text Insertion tab.
struct CursorContextReport {
  /// How much of the text around the cursor could be read.
  enum Quality: String, Codable, CaseIterable {
    /// A method read the text before the cursor.
    case good
    /// Something was read, but not enough to trust it fully (Monaco without screen reader
    /// mode: only the character before the cursor).
    case partial
    /// Nothing could be read: the text was pasted as dictated.
    case none

    static func of(_ resolution: CursorContextResolution, isMonacoWithoutScreenReader: Bool) -> Quality {
      guard resolution.method != nil else { return .none }
      return isMonacoWithoutScreenReader ? .partial : .good
    }
  }

  let context: CursorTextContext?
  let quality: Quality
  let place: PastePlace
}


/// Where a paste went: an app, or a website in a browser.
nonisolated struct PastePlace: Hashable {
  let bundleIdentifier: String?
  let appName: String
  /// Host of the web page, when the field is in a website ("vscode.dev").
  let website: String?

  /// Identifies the place in the paste history.
  var key: String {
    [bundleIdentifier ?? appName, website].compactMap { $0 }.joined(separator: "|")
  }

  /// "Cursor", or "vscode.dev (Dia)".
  var displayName: String {
    website.map { "\($0) (\(appName))" } ?? appName
  }
}
