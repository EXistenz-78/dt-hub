import Foundation

/// Una riga della tabella di riquadri che un prompt porta in coda (`<testo> [ {id, bbox, desc}, … ]` per un layout, o
/// `{id, from, src_bbox, tgt_bbox, desc}` per una modifica): riquadri sulla griglia 0–1000, `[y_min, x_min, y_max, x_max]`.
public struct PupBoxRow: Equatable, Sendable {
  public var id: String
  public var bbox: [Int]?
  public var from: String?
  public var src: [Int]?
  public var tgt: [Int]?
  public var desc: String

  public init(id: String, bbox: [Int]? = nil, from: String? = nil, src: [Int]? = nil, tgt: [Int]? = nil, desc: String) {
    self.id = id
    self.bbox = bbox
    self.from = from
    self.src = src
    self.tgt = tgt
    self.desc = desc
  }

  /// Una riga di modifica (`from`, `src_bbox`, `tgt_bbox`) e non di layout (`bbox`).
  var isEdit: Bool { bbox == nil }
}

/// Il prompt con una tabella di riquadri e il PUP di BFL (`flux-3-image-klein-pup`): port di `flux3/bbox.py` (Apache-2.0). Un prompt così
/// non va al `t2i`/`i2i` semplice ma al `t2i_bbox`/`i2i_bbox`, con le righe come annotazioni «bloccate» che il modello non può cambiare.
enum PupBoxes {
  /// Il testo e le righe, quando il prompt finisce con una tabella di riquadri (come `bbox.detect`); `[SALE]` o un elenco di numeri no.
  static func detect(_ prompt: String) -> (prompt: String, rows: [PupBoxRow])? {
    let (text, rows) = split(prompt)
    guard let rows, !rows.isEmpty, rows.allSatisfy({ isRow($0) }) else { return nil }
    return (text, rows)
  }

  /// «testo [righe]»: la `[` più a destra da cui il resto è un elenco JSON di dizionari (le `desc` possono avere parentesi).
  static func split(_ original: String) -> (text: String, rows: [PupBoxRow]?) {
    let text = original.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.joined(separator: "\n")
    let characters = Array(text)
    var index = characters.count - 1
    while index >= 0 {
      if characters[index] == "[" {
        let rest = String(characters[index...])
        if let object = try? JSONSerialization.jsonObject(with: Data(rest.utf8)), let list = object as? [Any],
          list.allSatisfy({ $0 is [String: Any] })
        {
          return (String(characters[..<index]).trimmingCharacters(in: .whitespacesAndNewlines), list.compactMap { ($0 as? [String: Any]).map(row) })
        }
      }
      index -= 1
    }
    return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
  }

  private static func row(_ object: [String: Any]) -> PupBoxRow {
    func box(_ key: String) -> [Int]? {
      guard let list = object[key] as? [Any] else { return nil }
      let numbers = list.compactMap { ($0 as? NSNumber)?.intValue }
      return numbers.count == list.count ? numbers : nil
    }
    return PupBoxRow(
      id: object["id"] as? String ?? "", bbox: box("bbox"), from: object["from"] as? String, src: box("src_bbox"), tgt: box("tgt_bbox"),
      desc: object["desc"] as? String ?? "")
  }

  private static func isRow(_ row: PupBoxRow) -> Bool {
    isID(row.id) && (validBox(row.bbox) || validBox(row.src) || validBox(row.tgt))
  }

  private static func isID(_ id: String) -> Bool { id.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil }

  /// Quattro interi sulla griglia 0–1000 con i lati in ordine; `max ≤ 1` sono coordinate 0–1, non la griglia.
  static func validBox(_ box: [Int]?) -> Bool {
    guard let box, box.count == 4 else { return false }
    let (y0, x0, y1, x1) = (box[0], box[1], box[2], box[3])
    return y0 >= 0 && x0 >= 0 && y1 > y0 && x1 > x0 && y1 <= 1000 && x1 <= 1000 && (box.max() ?? 0) > 1
  }

  /// Le righe come le scrive `json.dumps` di Python (`", "` e `": "`), su una riga.
  static func json(_ rows: [PupBoxRow]) -> String {
    func text(_ value: String) -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes]
      return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
    func box(_ box: [Int]?) -> String { box.map { "[" + $0.map(String.init).joined(separator: ", ") + "]" } ?? "null" }
    let items = rows.map { row -> String in
      if !row.isEdit { return "{\"id\": \(text(row.id)), \"bbox\": \(box(row.bbox)), \"desc\": \(text(row.desc))}" }
      return "{\"id\": \(text(row.id)), \"from\": \(row.from.map(text) ?? "null"), \"src_bbox\": \(box(row.src)), \"tgt_bbox\": \(box(row.tgt)), \"desc\": \(text(row.desc))}"
    }
    return "[" + items.joined(separator: ", ") + "]"
  }

  /// `upsampling_input` di BFL: il testo e le righe bloccate.
  static func upsamplingInput(prompt: String, rows: [PupBoxRow]) -> String {
    "ORIGINAL PROMPT:\n\(prompt.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
      + "LOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). "
      + "This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:\n"
      + json(rows)
  }

  /// `I2I_SCAFFOLD[True]` di BFL: la richiesta di modifica con le immagini allegate.
  static func editScaffold(_ instruction: String) -> String {
    "Reference images follow in attachment order: ref_image_0, ref_image_1, ...\nUser editing instruction: \(instruction)\n"
      + "Decide the edit, imagine the target image, and output the annotation record."
  }

  /// La risposta del modello con i nostri riquadri rimessi (`bbox.reconcile`): una riga che rifà un nostro riquadro (IoU ≥ 0,9) prende il
  /// nostro id, nelle righe e nelle citazioni; le nostre righe restano identiche e adottano la `desc` del modello; le righe che il modello
  /// aggiunge restano se valide e citate. Nil se la risposta non ha una tabella in fondo.
  static func reconcile(_ answer: String, locked: [PupBoxRow]) -> String? {
    var (caption, parsed) = split(answer)
    guard var rows = parsed else { return nil }
    let lockedIDs = Set(locked.map(\.id))
    var renamed: [String: String] = [:]
    for lock in locked {
      guard !rows.contains(where: { $0.id == lock.id }), let lockBox = lock.bbox ?? lock.tgt ?? lock.src else { continue }
      for row in rows where renamed[row.id] == nil && !lockedIDs.contains(row.id) {
        if let box = row.bbox ?? row.tgt ?? row.src, validBox(box), iou(box, lockBox) >= 0.9 {
          renamed[row.id] = lock.id
          break
        }
      }
    }
    for index in rows.indices { if let new = renamed[rows[index].id] { rows[index].id = new } }
    for (old, new) in renamed { caption = caption.replacingOccurrences(of: "<\(old)>", with: "<\(new)>") }
    var byID: [String: PupBoxRow] = [:]
    for row in rows where byID[row.id] == nil { byID[row.id] = row }
    var out = locked.map { lock -> PupBoxRow in
      var row = lock
      if let desc = byID[lock.id]?.desc.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty { row.desc = desc }
      return row
    }
    for row in rows {
      guard let added = validAdded(row, caption: caption), !out.contains(where: { $0.id == added.id }) else { continue }
      out.append(added)
    }
    return caption + " " + json(out)
  }

  private static func validAdded(_ row: PupBoxRow, caption: String) -> PupBoxRow? {
    guard isID(row.id), caption.contains("<\(row.id)>") else { return nil }
    let desc = row.desc.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !desc.isEmpty else { return nil }
    if validBox(row.bbox) { return PupBoxRow(id: row.id, bbox: row.bbox, desc: desc) }
    guard let origin = row.from, origin.range(of: "^(ref_image_\\d+|target)$", options: .regularExpression) != nil else { return nil }
    if row.src != nil && !validBox(row.src) { return nil }
    if row.tgt != nil && !validBox(row.tgt) { return nil }
    if row.src == nil && row.tgt == nil { return nil }
    if (origin == "target") == (row.src != nil) { return nil }
    return PupBoxRow(id: row.id, from: origin, src: row.src, tgt: row.tgt, desc: desc)
  }

  static func iou(_ a: [Int], _ b: [Int]) -> Double {
    let inter = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    let union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return union > 0 ? Double(inter) / Double(union) : 0
  }
}
