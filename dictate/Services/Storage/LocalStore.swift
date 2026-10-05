import Foundation
import OSLog
import SwiftData


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "LocalStore")


/// The app's on-device database: SwiftData, stored as SQLite in Application Support.
/// One container for the whole app. Add new models to `schema`.
///
/// Unit tests get an in-memory store, so they never read or change the user's data.
enum LocalStore {
  static let schema = Schema([ContextPasteApp.self])

  static let container: ModelContainer = {
    do {
      return try makeContainer(inMemory: AppEnvironment.isRunningTests)
    } catch {
      // A store that can't be opened shouldn't stop dictation: keep going in memory.
      logger.fault("Couldn't open the local store, falling back to memory: \(error, privacy: .public)")
      return try! makeContainer(inMemory: true)
    }
  }()

  static func makeContainer(inMemory: Bool) throws -> ModelContainer {
    try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
  }
}
