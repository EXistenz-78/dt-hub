import Foundation

/// Gli automatismi del campo di testo (spec §5): digitando `<e` diventa `<el_`, `<r` diventa `<ref_image_`, e la prima cifra
/// dopo l'uno o l'altro chiude con `>` (il cursore resta davanti al `>`, così un numero a due cifre si completa).
/// Funzione pura sul testo prima e dopo un'unica battuta; il cursore è un numero di caratteri.
enum ProseAutocomplete {
  struct Completion: Equatable {
    var text: String
    var caret: Int
  }

  static let prefixes = ["<el_", "<ref_image_"]

  /// `new` è `old` con un carattere in più, appena battuto prima del cursore (`caret`, dopo la battuta). Nil se non c'è niente
  /// da completare (un'altra lettera, una cancellazione, un incolla di più caratteri).
  static func complete(old: String, new: String, caret: Int) -> Completion? {
    let (oldChars, newChars) = (Array(old), Array(new))
    guard newChars.count == oldChars.count + 1, (1...newChars.count).contains(caret) else { return nil }
    var withoutTyped = newChars
    let typed = withoutTyped.remove(at: caret - 1)
    guard withoutTyped == oldChars else { return nil }
    let before = Array(newChars[..<(caret - 1)]), after = Array(newChars[caret...])

    if before.last == "<" {
      let expansion: String
      switch typed.lowercased() {
      case "e": expansion = "el_"
      case "r": expansion = "ref_image_"
      default: return nil
      }
      return Completion(text: String(before) + expansion + String(after), caret: before.count + expansion.count)
    }

    guard typed.isASCII, typed.isNumber else { return nil }
    var head = before
    while let last = head.last, last.isASCII, last.isNumber { head.removeLast() }
    guard prefixes.contains(where: { String(head).hasSuffix($0) }), after.first != ">" else { return nil }
    return Completion(text: String(before) + String(typed) + ">" + String(after), caret: before.count + 1)
  }
}
