import Foundation

struct F3Rename: Equatable, Sendable {
  var from: String
  var to: String
}

struct F3SyncChange: Equatable, Sendable {
  var added: [String] = []
  var removed: [String] = []
  var renamed: [F3Rename] = []
  var duplicates: [String] = []
}

/// Gli elementi nati dagli id della composizione (spec §7). Il testo è l'unica fonte degli id.
struct F3Sync: Equatable, Sendable {
  var elements: [F3Element] = []
  /// Gli elementi tolti dal testo, ricordati per la sessione: se lo stesso id ricompare tornano com'erano.
  var removed: [String: F3Element] = [:]
  /// Il prossimo colore da dare: cresce sempre, così un colore non cambia mai.
  var nextColor = 0

  /// Porta gli elementi in accordo col testo nuovo. `makeBox` riceve il numero di elementi già presenti.
  mutating func apply(oldText: String, newText: String, makeBox: (Int) -> BBox) -> F3SyncChange {
    var change = F3SyncChange()
    let oldMatches = F3IDParser.ids(in: oldText)
    let newMatches = F3IDParser.ids(in: newText)
    var seen = Set<String>(), reportedDuplicates = Set<String>()
    var newIDs: [String] = []
    for match in newMatches {
      if seen.insert(match.id).inserted { newIDs.append(match.id) } else if reportedDuplicates.insert(match.id).inserted {
        change.duplicates.append(match.id)
      }
    }
    let current = Set(elements.map(\.id))
    let gone = elements.map(\.id).filter { !seen.contains($0) }
    let fresh = newIDs.filter { !current.contains($0) }

    // Rinomina: nello stesso punto del testo un id sparisce e uno nuovo appare.
    var renames: [String: String] = [:]
    if oldMatches.count == newMatches.count {
      for (old, new) in zip(oldMatches, newMatches)
      where old.id != new.id && gone.contains(old.id) && fresh.contains(new.id) && renames[old.id] == nil
        && !renames.values.contains(new.id)
      {
        renames[old.id] = new.id
      }
    }
    for (from, to) in renames {
      if let index = elements.firstIndex(where: { $0.id == from }) { elements[index].id = to }
      change.renamed.append(F3Rename(from: from, to: to))
    }
    change.renamed.sort { $0.from < $1.from }

    for id in gone where renames[id] == nil {
      if let index = elements.firstIndex(where: { $0.id == id }) { removed[id] = elements.remove(at: index) }
      change.removed.append(id)
    }
    let renamedTo = Set(renames.values)
    for id in fresh where !renamedTo.contains(id) {
      if let back = removed.removeValue(forKey: id) {
        elements.append(back)
      } else {
        elements.append(F3Element(id: id, desc: "", box: makeBox(elements.count), colorIndex: nextColor, expanded: true))
        nextColor += 1
      }
      change.added.append(id)
    }
    return change
  }
}
