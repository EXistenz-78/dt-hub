import Foundation

/// Dove stanno i segnaposto nel testo e di che colore vanno (spec §5): `<id>` del colore del suo elemento (lo stesso del
/// riquadro e della scheda), `<ref_image_N>` neutro. Un segnaposto sconosciuto non si colora.
enum TagHighlight {
  struct Span: Equatable {
    var range: NSRange
    /// Il colore dell'elemento; nil per un'immagine.
    var colorIndex: Int?
  }

  static func spans(in text: String, colors: [String: Int]) -> [Span] {
    EditTags.matches(in: text).compactMap { match in
      let range = NSRange(match.range, in: text)
      if let index = colors[match.tag] { return Span(range: range, colorIndex: index) }
      if match.tag.hasPrefix("ref_image_") { return Span(range: range, colorIndex: nil) }
      return nil
    }
  }
}
