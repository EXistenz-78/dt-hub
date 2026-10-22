import Foundation

/// I segnaposto del testo: il contenuto di un `<…>` senza `<`, `>` né a capo, tolti gli spazi ai bordi, lungo 1–40 caratteri
/// (gli id degli elementi e `ref_image_N`).
enum EditTags {
  static let maxLength = 40

  struct Match: Equatable {
    var tag: String
    var range: Range<String.Index>
  }

  static func matches(in text: String) -> [Match] {
    var result: [Match] = []
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
        let tag = text[text.index(after: index)..<cursor].trimmingCharacters(in: .whitespaces)
        let end = text.index(after: cursor)
        if !tag.isEmpty, tag.count <= maxLength { result.append(Match(tag: tag, range: index..<end)) }
        index = end
      } else {
        index = text.index(after: index)
      }
    }
    return result
  }

  static func tags(in text: String) -> [String] { matches(in: text).map(\.tag) }

  /// Le parole tra virgolette dritte o ricurve.
  static func quoted(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|“([^”]+)”") else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      for group in 1...2 {
        if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
      }
      return nil
    }
  }
}

/// Un controllo grossolano, solo per l'italiano (la lingua dell'utente): un testo che l'LLM doveva tradurre in inglese e che è
/// rimasto italiano. Si contano le parole funzionali di una e dell'altra lingua; i segnaposto non contano.
enum EditLanguage {
  private static let italian: Set<String> = [
    "il", "lo", "la", "le", "gli", "un", "una", "uno", "di", "del", "dello", "della", "dei", "delle", "degli", "che", "con", "su",
    "sul", "sulla", "sui", "tra", "fra", "per", "e", "è", "sono", "si", "nel", "nella", "nei", "al", "alla", "alle", "da", "dal",
    "dalla", "dentro", "sullo", "sfondo", "ma", "non", "anche", "molto", "più", "aggiungi", "sposta", "modifica", "togli",
  ]
  private static let english: Set<String> = [
    "the", "a", "an", "of", "with", "and", "in", "on", "at", "is", "are", "to", "by", "from", "its", "her", "his", "their", "under",
    "over", "into", "behind", "next", "that", "which", "while",
  ]

  static func looksItalian(_ text: String) -> Bool {
    var clean = text
    for match in EditTags.matches(in: text).reversed() { clean.replaceSubrange(match.range, with: " ") }
    let words = clean.lowercased().split { !$0.isLetter }.map(String.init)
    let (it, en) = (words.filter { italian.contains($0) }.count, words.filter { english.contains($0) }.count)
    return it >= 2 && it > en
  }
}
