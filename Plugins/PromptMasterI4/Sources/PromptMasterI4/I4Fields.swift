import Foundation

/// A sentence a language model wrote for a field, with the input it was written for. When the field's input is not that
/// any more, the sentence is out of date and the raw text goes in the caption again.
struct WrittenPhrase: Codable, Equatable, Sendable {
  var text: String
  var input: String
}

/// Where a field stands for the language model.
enum FieldState: Equatable, Sendable {
  /// Nothing to write from.
  case empty
  /// The raw text goes in the caption: no sentence was written yet.
  case raw
  /// A sentence was written for the current input.
  case written
  /// A sentence was written, then the input changed.
  case stale
}

/// One field of the caption as the language model sees it (spec §7): what is sent, what was written, what goes out.
struct I4FieldInfo: Identifiable, Equatable, Sendable {
  /// The key of the field: `description`, `aesthetics`, `lighting`, `style`, `medium`, `background`, `element:<id>`.
  var id: String
  /// The tag of the field in the request and the answer.
  var tag: String
  /// The name the interface shows.
  var title: String
  /// `object` or `text` for an element.
  var kind: String?
  /// The lines of the block: what the sentence is written from. The words a lettering prints are never in it: a model
  /// that is given them writes them into the sentence, and the app adds them on its own.
  var lines: [String]
  /// What the sentence depends on: empty when there is nothing to write from.
  var input: String
  var raw: String
  var phrase: WrittenPhrase?
  var state: FieldState

  static let descriptionID = "description"
  static func elementID(_ id: Int) -> String { "element:\(id)" }

  /// What goes in the caption.
  var value: String { state == .written ? (phrase?.text ?? raw) : raw }
  /// There is something to write from, and no up-to-date sentence.
  var needsWriting: Bool { state == .raw || state == .stale }
  /// The text of the block in the request.
  var block: String { lines.joined(separator: "\n") }
}

extension I4Document {
  /// Every field of the caption in the order of the caption, with its input, raw text, sentence and state.
  func fields(catalog: I4Catalog) -> [I4FieldInfo] {
    func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    func termLines(_ field: I4Field) -> [String] {
      catalog.categories(for: field, mode: mode).compactMap { category in
        chosen(in: category).map { "\(category.en): \($0.en)" }
      }
    }
    func make(
      _ id: String, tag: String, title: String, kind: String? = nil, lines: [String], raw: String
    ) -> I4FieldInfo {
      let input = lines.isEmpty ? "" : ((kind.map { $0 + "\n" } ?? "") + lines.joined(separator: "\n"))
      let phrase = written[id]
      let state: FieldState
      if input.isEmpty {
        state = .empty
      } else if let phrase {
        state = phrase.input == input ? .written : .stale
      } else {
        state = .raw
      }
      return I4FieldInfo(
        id: id, tag: tag, title: title, kind: kind, lines: lines, input: input, raw: raw,
        phrase: phrase, state: state)
    }

    var result: [I4FieldInfo] = []
    let overview = trimmed(description)
    result.append(
      make(
        I4FieldInfo.descriptionID, tag: "high_level_description", title: "High level description",
        lines: overview.isEmpty ? [] : [overview], raw: overview))
    result.append(
      make(I4Field.aesthetics.rawValue, tag: "aesthetics", title: "Aesthetics", lines: termLines(.aesthetics),
        raw: rawText(.aesthetics, catalog: catalog)))
    result.append(
      make(I4Field.lighting.rawValue, tag: "lighting", title: "Lighting", lines: termLines(.lighting),
        raw: rawText(.lighting, catalog: catalog)))
    result.append(
      make(
        I4Field.style.rawValue, tag: mode == .photo ? "photo" : "art_style", title: mode == .photo ? "Photo" : "Art style",
        lines: termLines(.style), raw: rawText(.style, catalog: catalog)))
    result.append(
      make(I4Field.medium.rawValue, tag: "medium", title: "Medium", lines: termLines(.medium),
        raw: rawText(.medium, catalog: catalog)))
    let ownWords = trimmed(background)
    result.append(
      make(
        I4Field.background.rawValue, tag: "background", title: "Background",
        lines: (ownWords.isEmpty ? [] : [ownWords]) + termLines(.background), raw: rawBackground(catalog: catalog)))
    let lettering = catalog.categories(for: .lettering, mode: mode).first
    for (index, element) in elements.enumerated() {
      let words = trimmed(element.desc)
      var lines: [String] = []
      if element.type == .text {
        if !words.isEmpty { lines.append("Lettering style notes: \(words)") }
        if let id = element.lettering, let term = lettering?.terms.first(where: { $0.id == id }) {
          lines.append("\(lettering?.en ?? "Text & Lettering"): \(term.en)")
        }
      } else if !words.isEmpty {
        lines.append(words)
      }
      result.append(
        make(
          I4FieldInfo.elementID(element.id), tag: "element_\(index + 1)", title: "E\(index + 1) · \(element.type.rawValue)",
          kind: element.type == .text ? "text" : "object", lines: lines,
          raw: element.rawDescription(catalog: catalog)))
    }
    return result
  }

  /// The fields that have something to write from and no up-to-date sentence.
  func fieldsToWrite(catalog: I4Catalog) -> [I4FieldInfo] { fields(catalog: catalog).filter(\.needsWriting) }

  /// Keeps the sentences of the fields that still exist and still have something to write from.
  mutating func pruneWritten(catalog: I4Catalog) {
    let alive = Set(fields(catalog: catalog).filter { $0.state != .empty }.map(\.id))
    written = written.filter { alive.contains($0.key) }
  }
}
