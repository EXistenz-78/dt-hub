import Foundation

/// Una riga della tabella degli elementi nel formato del PUP e di FLUX.3: `{id, from, src_bbox, tgt_bbox, desc}` (riquadri 0–1000,
/// `[y0, x0, y1, x1]`). Port di `flux3/bbox.py` di BFL (Apache-2.0).
struct PupRow: Equatable, Sendable {
  var id: String
  /// `ref_image_N` o `target` (un oggetto nuovo); nil si scrive `null`.
  var from: String?
  var src: [Int]?
  var tgt: [Int]?
  var desc: String
}

extension PupRow {
  /// Una riga aggiunta dal modello in una scrittura di prima, come riga «bloccata».
  init(_ row: ExtraRow) {
    func ints(_ box: BBox?) -> [Int]? { box.map { [$0.y0, $0.x0, $0.y1, $0.x1] } }
    self.init(id: row.id, from: row.from, src: ints(row.src), tgt: ints(row.tgt), desc: row.desc)
  }
}

enum PupRecord {
  /// «paragrafo [righe]»: la `[` più a destra da cui il resto è un elenco JSON valido. Non una regex: le `desc` possono avere parentesi.
  static func split(_ original: String) -> (caption: String, rows: [PupRow]?) {
    // Alcuni modelli chiudono la tabella in un blocco di codice: le righe con ``` si tolgono.
    let text = original.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.joined(separator: "\n")
    let characters = Array(text)
    var index = characters.count - 1
    while index >= 0 {
      if characters[index] == "[" {
        let rest = String(characters[index...])
        // Solo un elenco di dizionari è una tabella (come `detect` di BFL): `[1, 2, 3, 4]` in coda è un riquadro, non la tabella.
        if let object = try? JSONSerialization.jsonObject(with: Data(rest.utf8)), let list = object as? [Any],
          list.allSatisfy({ $0 is [String: Any] })
        {
          let caption = String(characters[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
          return (caption, list.compactMap { ($0 as? [String: Any]).map(row) })
        }
      }
      index -= 1
    }
    return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
  }

  private static func row(_ object: [String: Any]) -> PupRow {
    func box(_ key: String) -> [Int]? {
      guard let list = object[key] as? [Any] else { return nil }
      let numbers = list.compactMap { ($0 as? NSNumber)?.intValue }
      return numbers.count == list.count ? numbers : nil
    }
    return PupRow(
      id: object["id"] as? String ?? "", from: object["from"] as? String, src: box("src_bbox"), tgt: box("tgt_bbox"),
      desc: object["desc"] as? String ?? "")
  }

  /// Le righe come le vuole il prompt: un array su una riga, con i `null` scritti e gli slash senza escape.
  static func json(_ rows: [PupRow]) -> String {
    func text(_ value: String) -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes]
      return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
    func box(_ box: [Int]?) -> String { box.map { "[" + $0.map(String.init).joined(separator: ", ") + "]" } ?? "null" }
    // Gli stessi separatori di `json.dumps` di Python (", " e ": "), che sono quelli con cui il modello è stato addestrato.
    let items = rows.map { row in
      "{\"id\": \(text(row.id)), \"from\": \(row.from.map(text) ?? "null"), \"src_bbox\": \(box(row.src)), \"tgt_bbox\": \(box(row.tgt)), \"desc\": \(text(row.desc))}"
    }
    return "[" + items.joined(separator: ", ") + "]"
  }
}

struct PupReconciled: Equatable, Sendable {
  /// Il paragrafo, con le citazioni `<id>` dei nostri id.
  var caption: String
  /// Le nostre righe, tali e quali, con la `desc` del modello.
  var rows: [PupRow]
  /// Le righe che il modello ha aggiunto e sono valide.
  var added: [PupRow]
  /// La risposta aveva una tabella in fondo (un elenco di dizionari).
  var hadList: Bool = true
}

enum PupReconcile {
  /// La risposta del modello con i nostri riquadri rimessi: una riga che rifà un nostro riquadro (IoU ≥ 0,9) prende il nostro id,
  /// nelle righe e nelle citazioni; le nostre righe restano identiche e adottano la `desc` del modello.
  static func reconcile(_ text: String, locked: [PupRow]) -> PupReconciled {
    var (caption, rows) = PupRecord.split(text)
    var list = rows ?? []
    let lockedIDs = Set(locked.map(\.id))
    var renamed: [String: String] = [:]
    for lock in locked {
      guard !list.contains(where: { $0.id == lock.id }), let lockBox = lock.tgt ?? lock.src else { continue }
      for row in list where renamed[row.id] == nil && !lockedIDs.contains(row.id) {
        if let box = row.tgt ?? row.src, validBox(box), iou(box, lockBox) >= 0.9 {
          renamed[row.id] = lock.id
          break
        }
      }
    }
    for index in list.indices { if let new = renamed[list[index].id] { list[index].id = new } }
    for (old, new) in renamed { caption = caption.replacingOccurrences(of: "<\(old)>", with: "<\(new)>") }
    var byID: [String: PupRow] = [:]
    for row in list where byID[row.id] == nil { byID[row.id] = row }
    let own = locked.map { lock -> PupRow in
      var row = lock
      if let desc = byID[lock.id]?.desc.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty { row.desc = desc }
      return row
    }
    var added: [PupRow] = []
    for row in list {
      guard let valid = validAdded(row, caption: caption), !lockedIDs.contains(valid.id), !added.contains(where: { $0.id == valid.id })
      else { continue }
      added.append(valid)
    }
    return PupReconciled(caption: caption, rows: own, added: added, hadList: rows != nil)
  }

  /// Una riga che il modello ha aggiunto: vale se l'id è citato come `<id>` nel paragrafo e la riga è ben fatta.
  static func validAdded(_ row: PupRow, caption: String) -> PupRow? {
    guard row.id.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil, caption.contains("<\(row.id)>") else { return nil }
    let desc = row.desc.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !desc.isEmpty, let origin = row.from, origin.range(of: "^(ref_image_\\d+|target)$", options: .regularExpression) != nil
    else { return nil }
    if row.src != nil && !validBox(row.src) { return nil }
    if row.tgt != nil && !validBox(row.tgt) { return nil }
    if row.src == nil && row.tgt == nil { return nil }
    if (origin == "target") == (row.src != nil) { return nil }
    return PupRow(id: row.id, from: origin, src: row.src, tgt: row.tgt, desc: desc)
  }

  static func iou(_ a: [Int], _ b: [Int]) -> Double {
    let inter = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    let union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return union > 0 ? Double(inter) / Double(union) : 0
  }

  /// Quattro interi nella griglia 0–1000, con i lati in ordine; `max ≤ 1` sono coordinate 0–1, non la griglia.
  static func validBox(_ box: [Int]?) -> Bool {
    guard let box, box.count == 4 else { return false }
    let (y0, x0, y1, x1) = (box[0], box[1], box[2], box[3])
    return y0 >= 0 && x0 >= 0 && y1 > y0 && x1 > x0 && y1 <= 1000 && x1 <= 1000 && (box.max() ?? 0) > 1
  }
}
