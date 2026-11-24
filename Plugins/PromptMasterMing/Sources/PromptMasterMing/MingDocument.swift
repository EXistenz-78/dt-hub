import Foundation

/// I due tipi di livello del builder di Ming: un oggetto (descrizione libera) o un testo (le parole esatte e il loro aspetto).
enum MingKind: String, Codable, CaseIterable, Sendable { case object, text }

/// Un livello: un riquadro con la sua descrizione. L'elenco va dallo sfondo (il primo) al primo piano (l'ultimo), come i
/// `layers` del JSON di Ming.
struct MingLayer: Codable, Equatable, Identifiable, Sendable {
  var id: Int
  var kind: MingKind
  /// Per un oggetto la descrizione intera; per un testo l'aspetto delle lettere (senza le parole).
  var description: String
  /// Le parole esatte di un testo (contano solo per il tipo Testo), a capo e maiuscole compresi.
  var text: String
  /// `hierarchy_and_relation`.
  var relation: String
  /// `color_specs`, `#RRGGBB`.
  var colors: [String]
  var box: FracBox
  var expanded: Bool
  /// La descrizione come è arrivata da un JSON importato: si riscrive identica finché testo e aspetto restano quelli che se ne
  /// sono ricavati (come `raw_description` del nodo ComfyUI).
  var rawDescription: String?
  /// Il testo e l'aspetto che se ne sono ricavati all'import: finché l'aspetto è quello, si riscrive `rawDescription`.
  var importedText: String?
  var importedVisual: String?
}

/// Tutto ciò che il tab ricorda del lavoro. La dimensione della Generazione non ne fa parte.
struct MingDocument: Codable, Equatable, Sendable {
  /// L'idea in parole libere, in qualsiasi lingua: la legge «Componi con LLM», non va nel JSON.
  var idea = ""
  var mode: StyleMode = .art
  /// Voci del database scelte (id dei termini): quelle della luce vanno in `ambient_lighting`, le altre in `image_style`.
  var selection: Set<String> = []
  /// `canvas_settings.image_style`.
  var imageStyle = ""
  /// `canvas_settings.ambient_lighting`.
  var ambientLighting = ""
  var layers: [MingLayer] = []
  var nextLayerID = 1
  var snapshot: MingSnapshot?
}
