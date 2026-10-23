import Foundation

/// I cinque tipi di elemento di MOSS: i tre del compilatore ufficiale più `panel` e `subject` degli esempi (il modello li accetta).
enum MossLabel: String, Codable, CaseIterable, Sendable { case object, character, text, panel, subject }

/// `summary.canvas`: una scena, più riquadri, un collage.
enum MossCanvas: String, Codable, CaseIterable, Sendable { case single, multi_panel, collage }

/// Un elemento: un riquadro con la sua descrizione. `tags` è testo separato da virgole; `text` conta solo per il tipo Testo.
struct MossItem: Codable, Equatable, Identifiable, Sendable {
  var id: Int
  var label: MossLabel
  var caption: String
  var text: String
  var tags: String
  var colors: [String]
  var box: FracBox
  var expanded: Bool

  /// I tag come lista: separati da virgole, senza spazi ai bordi, senza vuoti.
  var tagList: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

/// Tutto ciò che il tab ricorda del lavoro (spec §10). La dimensione della Generazione non ne fa parte.
struct MossDocument: Codable, Equatable, Sendable {
  var description = ""
  var mode: StyleMode = .photo
  /// Voci del database scelte (id dei termini): quelle di `meta` e quelle della caption.
  var selection: Set<String> = []
  var freeMeta: [String] = []
  var canvas: MossCanvas = .single
  var palette: [String] = []
  /// Voci del negativo scelte e testo libero; parte con le due più usate negli esempi ufficiali.
  var negativeSelection: Set<String> = ["ng_worst_quality", "ng_bad_anatomy"]
  var negativeText = ""
  var items: [MossItem] = []
  var nextItemID = 1
  var snapshot: MossSnapshot?
}
