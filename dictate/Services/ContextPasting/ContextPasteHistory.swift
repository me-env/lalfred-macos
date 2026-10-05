import Foundation
import OSLog
import SwiftData


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "ContextPasteHistory")


protocol ContextPasteRecording {
  func record(_ report: CursorContextReport)
}


/// Counts, per app or website, how well the context of each paste could be read.
struct ContextPasteHistory: ContextPasteRecording {
  var context: ModelContext = LocalStore.container.mainContext
  var now: () -> Date = Date.init

  func record(_ report: CursorContextReport) {
    let key = report.place.key
    let existing = try? context.fetch(FetchDescriptor<ContextPasteApp>(predicate: #Predicate { $0.key == key })).first
    if let existing {
      existing.count(report.quality, at: now())
      // Names can change (app renamed, localized): keep the latest.
      existing.appName = report.place.appName
    } else {
      let app = ContextPasteApp(place: report.place, quality: report.quality, at: now())
      app.count(report.quality, at: now())
      context.insert(app)
    }
    do {
      try context.save()
    } catch {
      logger.error("Couldn't save the paste history: \(error, privacy: .public)")
    }
  }

  func clear() {
    do {
      try context.delete(model: ContextPasteApp.self)
      try context.save()
    } catch {
      logger.error("Couldn't clear the paste history: \(error, privacy: .public)")
    }
  }
}
