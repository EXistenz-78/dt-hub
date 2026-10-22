import Foundation

/// Che cosa fa un riquadro (spec §2). Le coordinate stanno in `src`/`tgt` così:
/// `fromReference` — `src` sull'immagine del Moodboard `refFile`, `tgt` sul canvas;
/// `new` — solo `tgt`; `existing` e `remove` — solo `src` (sul canvas; per `existing` la destinazione è la stessa);
/// `move` — `src` e `tgt`, tutti e due sul canvas.
enum EditKind: String, Codable, Sendable {
  case fromReference, new, existing, move, remove
}

struct EditElement: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var colorIndex: Int
  var kind: EditKind
  /// Il file dell'immagine del Moodboard (solo `fromReference`): l'immagine si riconosce dal nome del file, non dal numero.
  var refFile: String?
  var src: BBox?
  var tgt: BBox?
  var desc: String
}
