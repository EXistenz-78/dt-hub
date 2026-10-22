import Foundation

/// Un controllo grossolano, solo per l'italiano (la lingua dell'utente): un testo che l'LLM doveva tradurre in inglese e che è
/// rimasto italiano. Si contano le parole funzionali (articoli, preposizioni) dell'una e dell'altra lingua; gli `<id>` non contano.
enum F3Language {
  private static let italian: Set<String> = [
    "il", "lo", "la", "le", "gli", "un", "una", "uno", "di", "del", "dello", "della", "dei", "delle", "degli", "che", "con", "su",
    "sul", "sulla", "sui", "tra", "fra", "per", "e", "è", "sono", "si", "nel", "nella", "nei", "al", "alla", "alle", "da", "dal",
    "dalla", "regge", "dentro", "sullo", "sfondo", "ma", "non", "anche", "molto", "più",
  ]
  private static let english: Set<String> = [
    "the", "a", "an", "of", "with", "and", "in", "on", "at", "is", "are", "to", "by", "from", "its", "her", "his", "their", "under",
    "over", "into", "behind", "next", "that", "which", "while",
  ]

  static func looksItalian(_ text: String) -> Bool {
    var clean = text
    for match in F3IDParser.ids(in: text).reversed() { clean.replaceSubrange(match.range, with: " ") }
    let words = clean.lowercased().split { !$0.isLetter }.map(String.init)
    let (it, en) = (words.filter { italian.contains($0) }.count, words.filter { english.contains($0) }.count)
    return it >= 2 && it > en
  }
}
