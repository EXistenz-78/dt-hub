import CoreGraphics
import Foundation

/// I quattro angoli di un riquadro che si trascinano per ridimensionarlo.
enum CanvasCorner: CaseIterable, Sendable { case nw, ne, sw, se }

/// Un riquadro sulla tela con quello che serve a disegnarlo e a capire se lo si tocca: l'id, il numero sull'etichetta
/// (la posizione nell'elenco), il tipo e il box in frazioni.
struct CanvasItem: Equatable, Sendable {
  var id: Int
  var number: Int
  var label: MossLabel
  var box: FracBox

  /// Quello che dice l'etichetta: `E1 · object`.
  var tag: String { "E\(number) · \(label.rawValue)" }
}

/// Cosa fa un gesto sulla tela, deciso dove comincia.
enum CanvasMode: Equatable, Sendable {
  /// Disegna un nuovo box.
  case draw
  /// Sposta il box `id`, che era `original` quando il gesto è cominciato.
  case move(id: Int, original: FracBox)
  /// Trascina l'angolo `corner` del box `id`; l'angolo opposto resta fermo.
  case resize(id: Int, corner: CanvasCorner, original: FracBox)
  /// Preme l'etichetta del box `id` (apre il menu dei tipi).
  case tag(id: Int)
}

/// Un gesto: dove è cominciato e dove sta il puntatore, in punti della tela.
struct CanvasDrag: Equatable, Sendable {
  var mode: CanvasMode
  var start: CGPoint
  var current: CGPoint

  /// Meno di tanti punti è un clic, non un trascinamento.
  static let clickDistance: CGFloat = 3

  var moved: Bool { hypot(current.x - start.x, current.y - start.y) >= Self.clickDistance }
}

/// La geometria della tela, a parte SwiftUI: punti ↔ frazioni 0–1, che gesto comincia con una pressione e cosa fa un gesto a un
/// box (spec §6). `size` è la tela in punti; `pixels` la Generazione, che fissa il lato minimo (il 2 % del lato corto).
struct CanvasGeometry: Equatable, Sendable {
  var size: CGSize
  var pixels: PixelSize

  static let handleRadius: CGFloat = 12
  static let tagHeight: CGFloat = 18

  private var isUsable: Bool { size.width > 0 && size.height > 0 }

  // MARK: Punti e frazioni

  /// Il punto in frazioni, tenuto dentro la tela.
  func fraction(_ point: CGPoint) -> (x: Double, y: Double) {
    guard isUsable else { return (0, 0) }
    func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    return (clamp(Double(point.x / size.width)), clamp(Double(point.y / size.height)))
  }

  /// Di quanto si è mosso il puntatore, in frazioni, senza limite.
  func delta(from a: CGPoint, to b: CGPoint) -> (dx: Double, dy: Double) {
    guard isUsable else { return (0, 0) }
    return (Double((b.x - a.x) / size.width), Double((b.y - a.y) / size.height))
  }

  func rect(of box: FracBox) -> CGRect {
    CGRect(
      x: CGFloat(box.x0) * size.width, y: CGFloat(box.y0) * size.height,
      width: CGFloat(box.x1 - box.x0) * size.width, height: CGFloat(box.y1 - box.y0) * size.height)
  }

  func handlePoint(_ corner: CanvasCorner, of rect: CGRect) -> CGPoint {
    switch corner {
    case .nw: return CGPoint(x: rect.minX, y: rect.minY)
    case .ne: return CGPoint(x: rect.maxX, y: rect.minY)
    case .sw: return CGPoint(x: rect.minX, y: rect.maxY)
    case .se: return CGPoint(x: rect.maxX, y: rect.maxY)
    }
  }

  /// Dov'è l'etichetta di un box: sopra l'angolo in alto a sinistra, o dentro il box se sopra non c'è posto, mai oltre il bordo
  /// destro della tela.
  func tagRect(for item: CanvasItem, boxRect: CGRect? = nil) -> CGRect {
    let box = boxRect ?? rect(of: item.box)
    let width = CGFloat(item.tag.count) * 7 + 22
    let above = box.minY - Self.tagHeight - 2
    let y = above >= 0 ? above : box.minY + 2
    let x = max(0, min(box.minX, size.width - width))
    return CGRect(x: x, y: y, width: width, height: Self.tagHeight)
  }

  // MARK: Dove comincia una pressione

  /// Cosa comincia con una pressione in `point`. L'etichetta del box selezionato viene prima (è disegnata sopra), poi gli
  /// angoli del box selezionato, poi le altre etichette (prima il box più in alto), poi i box (prima il selezionato, poi il più
  /// in alto); altrove si disegna. `items` sono nell'ordine dell'elenco, che è l'ordine di sovrapposizione.
  func begin(at point: CGPoint, items: [CanvasItem], selected: Int?) -> CanvasMode {
    guard isUsable else { return .draw }
    let chosen = items.first { $0.id == selected }
    if let chosen, tagRect(for: chosen).contains(point) { return .tag(id: chosen.id) }
    if let chosen {
      let box = rect(of: chosen.box)
      for corner in CanvasCorner.allCases {
        let handle = handlePoint(corner, of: box)
        if hypot(point.x - handle.x, point.y - handle.y) <= Self.handleRadius {
          return .resize(id: chosen.id, corner: corner, original: chosen.box)
        }
      }
    }
    for item in items.reversed() where tagRect(for: item).contains(point) { return .tag(id: item.id) }
    let ordered = items.filter { $0.id == selected } + items.reversed().filter { $0.id != selected }
    for item in ordered where rect(of: item.box).contains(point) { return .move(id: item.id, original: item.box) }
    return .draw
  }

  // MARK: Cosa fa un gesto

  /// Il rettangolo da mostrare mentre il gesto va avanti (nil per una pressione su un'etichetta).
  func preview(of drag: CanvasDrag) -> FracBox? {
    switch drag.mode {
    case .draw:
      let a = fraction(drag.start), b = fraction(drag.current)
      return FracBox(x0: min(a.x, b.x), y0: min(a.y, b.y), x1: max(a.x, b.x), y1: max(a.y, b.y))
    case .move(_, let original):
      return Self.moved(original, by: delta(from: drag.start, to: drag.current))
    case .resize(_, let corner, let original):
      return resized(original, corner: corner, to: fraction(drag.current))
    case .tag:
      return nil
    }
  }

  /// Il box che il gesto lascia; nil se un box disegnato è troppo piccolo, o per un'etichetta.
  func result(of drag: CanvasDrag) -> FracBox? {
    switch drag.mode {
    case .draw, .resize:
      guard let area = preview(of: drag) else { return nil }
      return FracBox.normalized(x0: area.x0, y0: area.y0, x1: area.x1, y1: area.y1, size: pixels)
    case .move:
      return preview(of: drag)
    case .tag:
      return nil
    }
  }

  /// `box` spostato di `delta`, con la sua dimensione e dentro la tela.
  static func moved(_ box: FracBox, by delta: (dx: Double, dy: Double)) -> FracBox {
    let (width, height) = (box.x1 - box.x0, box.y1 - box.y0)
    let x0 = min(max(box.x0 + delta.dx, 0), 1 - width), y0 = min(max(box.y0 + delta.dy, 0), 1 - height)
    return FracBox(x0: x0, y0: y0, x1: x0 + width, y1: y0 + height)
  }

  /// `original` con un angolo in `point` e l'angolo opposto fermo; ogni lato resta lungo almeno il minimo.
  private func resized(_ original: FracBox, corner: CanvasCorner, to point: (x: Double, y: Double)) -> FracBox {
    var area = original
    let least = FracBox.minimum(for: pixels)
    switch corner {
    case .nw, .ne: area.y0 = min(point.y, area.y1 - least.y)
    case .sw, .se: area.y1 = max(point.y, area.y0 + least.y)
    }
    switch corner {
    case .nw, .sw: area.x0 = min(point.x, area.x1 - least.x)
    case .ne, .se: area.x1 = max(point.x, area.x0 + least.x)
    }
    return area
  }

  // MARK: La forma della tela

  /// La dimensione più grande con le proporzioni `aspect` (larghezza / altezza) che sta in `available`; una proporzione senza
  /// senso è un quadrato.
  static func fit(aspect: Double, in available: CGSize) -> CGSize {
    guard available.width > 0, available.height > 0 else { return .zero }
    let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
    let byWidth = CGSize(width: available.width, height: available.width / ratio)
    if byWidth.height <= available.height { return byWidth }
    return CGSize(width: available.height * ratio, height: available.height)
  }
}

/// La dimensione della Generazione, come l'app la dice nel messaggio `context` (`parameters.width` e `.height`).
enum GenerationSize {
  static func read(fromContext data: Data) -> PixelSize? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let parameters = object["parameters"] as? [String: Any],
      let width = parameters["width"] as? Int, let height = parameters["height"] as? Int, width > 0, height > 0
    else { return nil }
    return PixelSize(width: width, height: height)
  }
}
