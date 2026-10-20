import Foundation

struct F3IDMatch: Equatable {
  var id: String
  /// L'intero `<…>` nel testo.
  var range: Range<String.Index>
}

/// Gli id della composizione (spec §7): il contenuto di un `<…>` senza `<`, `>` né a capo, tolti gli spazi ai bordi,
/// lungo 1–40 caratteri. Gli id sono liberi: nessun formato imposto.
enum F3IDParser {
  static let maxLength = 40

  static func ids(in text: String) -> [F3IDMatch] {
    var result: [F3IDMatch] = []
    var index = text.startIndex
    while index < text.endIndex {
      guard text[index] == "<" else { index = text.index(after: index); continue }
      var cursor = text.index(after: index)
      var closed = false
      while cursor < text.endIndex {
        let character = text[cursor]
        if character == ">" { closed = true; break }
        if character == "<" || character.isNewline { break }
        cursor = text.index(after: cursor)
      }
      if closed {
        let id = text[text.index(after: index)..<cursor].trimmingCharacters(in: .whitespaces)
        let end = text.index(after: cursor)
        if !id.isEmpty, id.count <= maxLength { result.append(F3IDMatch(id: id, range: index..<end)) }
        index = end
      } else {
        // Un `<` che apre di nuovo, o la fine: si riparte dal carattere dopo il primo `<`.
        index = text.index(after: index)
      }
    }
    return result
  }
}
