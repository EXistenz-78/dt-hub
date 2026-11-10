import Foundation

/// What a tab remembers between runs. The layout has a number: a session of another layout is ignored and the tab
/// starts empty.
protocol StoredSession: Codable {
  static var currentSchema: Int { get }
  /// The key of the session in `UserDefaults`, where it lived before DT Hub had projects.
  static var storageKey: String { get }
  var schema: Int { get }
  init()
}

/// Where a session is kept: a key and some bytes. `UserDefaults` in the app; the tests use a dictionary, so they leave
/// nothing in the user's preferences.
protocol SessionStorage {
  func data(forKey key: String) -> Data?
  func set(_ data: Data, forKey key: String)
}

struct DefaultsStorage: SessionStorage {
  var defaults: UserDefaults = .standard
  func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
  func set(_ data: Data, forKey key: String) { defaults.set(data, forKey: key) }
}

/// `state.json` in the folder the app gives the plug-in for the open project (the key does not matter: one file holds the
/// one session).
struct FileStorage: SessionStorage {
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
struct SessionStore<Session: StoredSession> {
  static var key: String { Session.storageKey }

  var storage: any SessionStorage = DefaultsStorage()
  var key: String = Session.storageKey

  func save(_ session: Session) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    storage.set(data, forKey: key)
  }

  func load() -> Session {
    guard let data = storage.data(forKey: key), let session = try? JSONDecoder().decode(Session.self, from: data),
      session.schema == Session.currentSchema
    else { return Session() }
    return session
  }

  /// The first project ever takes the session the tab had before projects (`legacy`, the `UserDefaults` one): copied into
  /// this storage, only if it has none yet.
  func adoptLegacy(from legacy: any SessionStorage) {
    guard storage.data(forKey: key) == nil, let data = legacy.data(forKey: key) else { return }
    storage.set(data, forKey: key)
  }
}
