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

/// The session in `UserDefaults`, under a key of its own.
struct I4Store {
  static let key = "com.exiztenz.dthub.promptmasteri4.state.v1"

  var defaults: UserDefaults = .standard
  var key: String = I4Store.key

  func save(_ session: I4Session) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    defaults.set(data, forKey: key)
  }

  func load() -> I4Session {
    guard let data = defaults.data(forKey: key), let session = try? JSONDecoder().decode(I4Session.self, from: data),
      session.schema == I4Session.currentSchema
    else { return I4Session() }
    return session
  }
}
