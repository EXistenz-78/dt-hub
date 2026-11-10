import Foundation

/// What the tab remembers between runs: the document, the JSON the user edited by hand and what is open. The layout has
/// a number: a session of another layout is ignored and the tab starts empty.
struct I4Session: StoredSession, Equatable {
  static let currentSchema = 1
  static let storageKey = "com.exiztenz.dthub.promptmasteri4.state.v1"

  var schema = I4Session.currentSchema
  var document = I4Document()
  /// The JSON the user changed by hand in the review window; it is what «Send» sends until it is restored.
  var editedJSON: String?
  var openSections: [String] = []
  var openCategories: [String] = []
  var expandedElements: [Int] = []
}

typealias I4Store = SessionStore<I4Session>
