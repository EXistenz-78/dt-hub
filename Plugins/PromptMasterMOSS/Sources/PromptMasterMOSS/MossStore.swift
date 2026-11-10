import Foundation

/// What the tab remembers between runs: the document, the JSON the user edited by hand and what is open. The layout has
/// a number: a session of another layout is ignored and the tab starts empty.
struct MossSession: StoredSession, Equatable {
  static let currentSchema = 1
  static let storageKey = "com.exiztenz.dthub.promptmastermoss.state.v1"

  var schema = MossSession.currentSchema
  var document = MossDocument()
  var openGroups: [String] = []
  var openCategories: [String] = []
}

typealias MossStore = SessionStore<MossSession>
