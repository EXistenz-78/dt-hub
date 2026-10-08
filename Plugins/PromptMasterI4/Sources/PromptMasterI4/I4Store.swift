import Foundation

/// What the tab remembers between runs: the document, the JSON the user edited by hand and what is open. The layout has
/// a number: a session of another layout is ignored and the tab starts empty.
struct I4Session: Codable, Equatable {
  static let currentSchema = 1

  var schema = I4Session.currentSchema
  var document = I4Document()
  /// The JSON the user changed by hand in the review window; it is what «Send» sends until it is restored.
  var editedJSON: String?
  var openSections: [String] = []
  var openCategories: [String] = []
  var expandedElements: [Int] = []
}

/// Where a session is kept: a key and some bytes. `UserDefaults` in the app; the tests use a dictionary, so they leave
/// nothing in the user's preferences.
protocol I4Storage {
  func data(forKey key: String) -> Data?
  func set(_ data: Data, forKey key: String)
}

struct DefaultsStorage: I4Storage {
  var defaults: UserDefaults = .standard
  func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
  func set(_ data: Data, forKey key: String) { defaults.set(data, forKey: key) }
}

/// `state.json` in the folder the app gives the plug-in for the open project (the key does not matter: one file holds the
/// one session).
struct FileStorage: I4Storage {
  static let fileName = "state.json"
  let folder: URL

  private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

  func data(forKey key: String) -> Data? { try? Data(contentsOf: fileURL) }

  func set(_ data: Data, forKey key: String) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}

/// The session in the storage, under a key of its own.
struct I4Store {
  static let key = "com.exiztenz.dthub.promptmasteri4.state.v1"

  var storage: any I4Storage = DefaultsStorage()
  var key: String = I4Store.key

  func save(_ session: I4Session) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    storage.set(data, forKey: key)
  }

  func load() -> I4Session {
    guard let data = storage.data(forKey: key), let session = try? JSONDecoder().decode(I4Session.self, from: data),
      session.schema == I4Session.currentSchema
    else { return I4Session() }
    return session
  }

  /// The first project ever takes the session the tab had before projects (`legacy`, the `UserDefaults` one): copied into
  /// this storage, only if it has none yet.
  func adoptLegacy(from legacy: any I4Storage) {
    guard storage.data(forKey: key) == nil, let data = legacy.data(forKey: key) else { return }
    storage.set(data, forKey: key)
  }
}
