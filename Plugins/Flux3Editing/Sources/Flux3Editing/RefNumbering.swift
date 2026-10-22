import CoreGraphics
import Foundation

/// Una delle immagini del Moodboard così come il modello le numera: `<ref_image_N>`.
struct RefImage: Equatable, Sendable {
  /// Da 1: lo 0 è l'immagine di partenza.
  let number: Int
  let path: String
  /// Le dimensioni del file (1×1 se non si leggono): le proporzioni della tela.
  let size: CGSize

  /// Il nome del file della copia nel progetto: così si riconosce l'immagine anche se cambia posizione nel Moodboard.
  var fileName: String { (path as NSString).lastPathComponent }
}

/// Come si numerano le immagini (spec §1, §4): `ref_image_0` è l'immagine di partenza, `ref_image_{i+1}` l'i-esima immagine
/// accesa del Moodboard. È l'**unico** punto che lo decide: se FLUX.3 si rivela diverso si cambia qui.
enum RefNumbering {
  static let startImageNumber = 0

  /// Le immagini accese del Moodboard (i percorsi del contesto, nell'ordine delle miniature), numerate da 1.
  static func references(moodboard: [String], sizes: (String) -> CGSize?) -> [RefImage] {
    moodboard.enumerated().map { index, path in
      RefImage(number: startImageNumber + index + 1, path: path, size: sizes(path) ?? CGSize(width: 1, height: 1))
    }
  }

  static func number(ofFile fileName: String, in refs: [RefImage]) -> Int? {
    refs.first { $0.fileName == fileName }?.number
  }
}
