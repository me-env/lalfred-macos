import Foundation
import SwiftData


/// An app or website the user dictated into with context pasting on, and how well its
/// context could be read there.
@Model
final class ContextPasteApp {
  /// ``PastePlace/key``: the bundle identifier, plus the website for browsers.
  var key: String
  var bundleIdentifier: String?
  var appName: String
  var website: String?
  var goodPastes = 0
  var partialPastes = 0
  var unreadPastes = 0
  var lastQualityRaw: String
  var lastPasteAt: Date

  init(place: PastePlace, quality: CursorContextReport.Quality, at date: Date) {
    key = place.key
    bundleIdentifier = place.bundleIdentifier
    appName = place.appName
    website = place.website
    lastQualityRaw = quality.rawValue
    lastPasteAt = date
  }

  var lastQuality: CursorContextReport.Quality {
    CursorContextReport.Quality(rawValue: lastQualityRaw) ?? .none
  }

  var pasteCount: Int { goodPastes + partialPastes + unreadPastes }

  func count(_ quality: CursorContextReport.Quality, at date: Date) {
    switch quality {
    case .good: goodPastes += 1
    case .partial: partialPastes += 1
    case .none: unreadPastes += 1
    }
    lastQualityRaw = quality.rawValue
    lastPasteAt = date
  }
}
