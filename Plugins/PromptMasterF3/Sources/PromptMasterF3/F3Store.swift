import Foundation

/// What the tab remembers between runs: the document, the JSON the user edited by hand and what is open. The layout has
/// a number: a session of another layout is ignored and the tab starts empty.
struct F3Session: StoredSession, Equatable {
  static let currentSchema = 1
  static let storageKey = "com.exiztenz.dthub.promptmasterf3.state.v1"

  var schema = F3Session.currentSchema
  var document = F3Document()
  var openGroups: [String] = []
  var openCategories: [String] = []
}

typealias F3Store = SessionStore<F3Session>
