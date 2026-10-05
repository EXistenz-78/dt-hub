import Foundation

/// What the tab remembers between runs: the text, the chosen terms, the Shuffle mode, the booru switch and which
/// groups and categories are open. The search is not kept.
struct PMSession: Codable, Equatable {
  var description = ""
  var selection: [String] = []
  var mode: StyleMode = .photo
  var booru = false
  var openGroups: [String] = []
  var openCategories: [String] = []
}

/// The session in `UserDefaults`, under a key of its own.
struct PMStore {
  static let key = "com.exiztenz.dthub.promptmaster.state.v1"

  var defaults: UserDefaults = .standard
  var key: String = PMStore.key

  func save(_ session: PMSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    defaults.set(data, forKey: key)
  }

  /// The saved session; a first run, or one that cannot be read, starts empty.
  func load() -> PMSession {
    guard let data = defaults.data(forKey: key), let session = try? JSONDecoder().decode(PMSession.self, from: data) else {
      return PMSession()
    }
    return session
  }
}
