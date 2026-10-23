import Foundation

/// I testi prima dell'ultima scrittura dell'LLM, per «Annulla» (spec §7). `restore` arriva con la scrittura (Task 6).
struct MossSnapshot: Codable, Equatable, Sendable {
  var description: String
  var selection: Set<String>
  var freeMeta: [String]
  /// `caption` e `tags` degli elementi, per id.
  var captions: [Int: String]
  var tags: [Int: String]
}
