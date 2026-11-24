import Foundation

/// What the tab remembers between runs: the document and what is open. The layout has a number: a session of another
/// layout is ignored and the tab starts empty.
struct MingSession: StoredSession, Equatable {
  static let currentSchema = 1
  static let storageKey = "com.exiztenz.dthub.promptmasterming.state.v1"

  var schema = MingSession.currentSchema
  var document = MingDocument()
  var openGroups: [String] = []
  var openCategories: [String] = []
}

typealias MingStore = SessionStore<MingSession>
