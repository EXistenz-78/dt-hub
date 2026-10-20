import Foundation

/// La fotografia dei testi presa prima di una scrittura dell'LLM (spec §9): serve ad «Annulla». Solo l'ultima.
struct F3Snapshot: Codable, Equatable, Sendable {
  var description: String
  var selection: Set<String>
  var composition: String
  /// La descrizione di ogni elemento, per id.
  var descs: [String: String]
}
