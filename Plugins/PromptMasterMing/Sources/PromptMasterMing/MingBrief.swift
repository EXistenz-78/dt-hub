import Foundation

/// Una parte da riscrivere: titolo e testo dell'utente (e, per stile e luce, le voci scelte come righe `Categoria: voce`).
struct MingPart: Equatable, Sendable {
  enum Kind: Hashable, Sendable {
    case imageStyle
    case ambientLighting
    case layer(id: Int, kind: MingKind)
    case relation(id: Int)

    /// Il titolo nel messaggio e nella risposta.
    var title: String {
      switch self {
      case .imageStyle: return "image_style"
      case .ambientLighting: return "ambient_lighting"
      case .layer(let id, let kind): return "layer \(id) (\(kind.rawValue))"
      case .relation(let id): return "relation \(id)"
      }
    }
  }

  var kind: Kind
  var text: String
  var terms: [String] = []

  var block: String { ([text] + terms).filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// Il messaggio all'LLM per «Scrivi con LLM»: blocchi Markdown con un titolo ciascuno. Mai le parole esatte dei Testi, né
/// coordinate o colori.
enum MingBrief {
  static func parts(from document: MingDocument, catalog: MingCatalog) -> [MingPart] {
    var parts: [MingPart] = []
    let style = document.imageStyle.trimmingCharacters(in: .whitespacesAndNewlines)
    let styleLines = catalog.styleLines(document.selection)
    if !style.isEmpty || !styleLines.isEmpty { parts.append(MingPart(kind: .imageStyle, text: style, terms: styleLines)) }
    let light = document.ambientLighting.trimmingCharacters(in: .whitespacesAndNewlines)
    let lightLines = catalog.lightingLines(document.selection)
    if !light.isEmpty || !lightLines.isEmpty { parts.append(MingPart(kind: .ambientLighting, text: light, terms: lightLines)) }
    for layer in document.layers {
      let description = layer.description.trimmingCharacters(in: .whitespacesAndNewlines)
      if !description.isEmpty { parts.append(MingPart(kind: .layer(id: layer.id, kind: layer.kind), text: description)) }
      let relation = layer.relation.trimmingCharacters(in: .whitespacesAndNewlines)
      if !relation.isEmpty { parts.append(MingPart(kind: .relation(id: layer.id), text: relation)) }
    }
    return parts
  }

  /// I blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(_ parts: [MingPart], reminder: String? = nil) -> String {
    var text = parts.map { "## \($0.kind.title)\n\($0.block)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }

  /// La richiesta di «Componi con LLM»: l'idea, le voci scelte, la forma della tela e, se ci sono già livelli, il JSON di adesso
  /// (così l'LLM lo cambia invece di ricominciare).
  static func composeMessage(idea: String, styleLines: [String], lightingLines: [String], size: PixelSize, currentJSON: String?) -> String {
    var text = "## request\n" + idea.trimmingCharacters(in: .whitespacesAndNewlines)
    let terms = styleLines + lightingLines
    if !terms.isEmpty { text += "\n\n## chosen terms (use them in image_style and ambient_lighting)\n" + terms.joined(separator: "\n") }
    let shape = size.width == size.height ? "square" : (size.width > size.height ? "landscape" : "portrait")
    text += "\n\n## canvas\n\(shape), \(size.width) x \(size.height) px. Write \"aspect_ratio\": \"\(MingGeometry.aspectRatio(size))\" and lay out every layer for this shape."
    if let currentJSON { text += "\n\n## current layout (change it as the request says)\n" + currentJSON }
    text += "\n\nReply with the JSON only."
    return text
  }
}
