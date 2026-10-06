import CoreGraphics
import Foundation

/// The corners of a box that can be dragged to resize it.
enum CanvasCorner: CaseIterable, Sendable { case nw, ne, sw, se }

/// A box on the canvas with what the canvas needs to draw and hit-test it: the element's id, its place in the list
/// (the number on its tag), its type and its box.
struct CanvasItem: Equatable, Sendable {
  var id: Int
  var number: Int
  var type: ElementType
  var box: BBox

  /// What the tag says: `E1 · obj`, `E2 · text`.
  var label: String { "E\(number) · \(type.rawValue)" }
}

/// What a gesture on the canvas is doing, decided where it started.
enum CanvasMode: Equatable, Sendable {
  /// Drawing a new box.
  case draw
  /// Moving the box `id`, which was `original` when the gesture began.
  case move(id: Int, original: BBox)
  /// Dragging the `corner` of the box `id`; the opposite corner stays where it was.
  case resize(id: Int, corner: CanvasCorner, original: BBox)
  /// Pressing the tag of the box `id`.
  case tag(id: Int)
}

/// One gesture: where it began, where the pointer is now, in points of the canvas.
struct CanvasDrag: Equatable, Sendable {
  var mode: CanvasMode
  var start: CGPoint
  var current: CGPoint

  /// Less than this many points is a click, not a drag.
  static let clickDistance: CGFloat = 3

  var moved: Bool { hypot(current.x - start.x, current.y - start.y) >= Self.clickDistance }
}

/// A rectangle on the 0…1000 grid, before it is rounded to a box: `y0 <= y1` and `x0 <= x1`.
struct GridRect: Equatable, Sendable {
  var y0: Double
  var x0: Double
  var y1: Double
  var x1: Double
}

/// The geometry of the canvas, apart from SwiftUI: points ↔ the 0…1000 grid, which gesture a press starts, and what a
/// gesture makes of a box (spec §5). `size` is the canvas in points.
struct CanvasGeometry: Equatable, Sendable {
  var size: CGSize

  static let handleRadius: CGFloat = 12
  static let tagHeight: CGFloat = 18

  private var isUsable: Bool { size.width > 0 && size.height > 0 }

  // MARK: Points and the grid

  /// The point on the grid, kept inside it.
  func grid(_ point: CGPoint) -> (x: Double, y: Double) {
    guard isUsable else { return (0, 0) }
    func clamp(_ value: Double) -> Double { min(max(value, 0), Double(BBox.grid)) }
    return (clamp(Double(point.x / size.width) * 1000), clamp(Double(point.y / size.height) * 1000))
  }

  /// How far the pointer went, in grid units, with no limit.
  func delta(from a: CGPoint, to b: CGPoint) -> (dx: Double, dy: Double) {
    guard isUsable else { return (0, 0) }
    return (Double((b.x - a.x) / size.width) * 1000, Double((b.y - a.y) / size.height) * 1000)
  }

  func rect(of box: BBox) -> CGRect {
    CGRect(
      x: CGFloat(box.x0) / 1000 * size.width, y: CGFloat(box.y0) / 1000 * size.height,
      width: CGFloat(box.x1 - box.x0) / 1000 * size.width, height: CGFloat(box.y1 - box.y0) / 1000 * size.height)
  }

  func rect(of grid: GridRect) -> CGRect {
    CGRect(
      x: CGFloat(grid.x0) / 1000 * size.width, y: CGFloat(grid.y0) / 1000 * size.height,
      width: CGFloat(grid.x1 - grid.x0) / 1000 * size.width, height: CGFloat(grid.y1 - grid.y0) / 1000 * size.height)
  }

  func handlePoint(_ corner: CanvasCorner, of rect: CGRect) -> CGPoint {
    switch corner {
    case .nw: return CGPoint(x: rect.minX, y: rect.minY)
    case .ne: return CGPoint(x: rect.maxX, y: rect.minY)
    case .sw: return CGPoint(x: rect.minX, y: rect.maxY)
    case .se: return CGPoint(x: rect.maxX, y: rect.maxY)
    }
  }

  /// Where the tag of a box is: above its top left corner, or inside the box when there is no room above, and never
  /// beyond the right edge of the canvas.
  func tagRect(for item: CanvasItem, boxRect: CGRect? = nil) -> CGRect {
    let box = boxRect ?? rect(of: item.box)
    let width = CGFloat(item.label.count) * 7 + 14
    let above = box.minY - Self.tagHeight - 2
    let y = above >= 0 ? above : box.minY + 2
    let x = max(0, min(box.minX, size.width - width))
    return CGRect(x: x, y: y, width: width, height: Self.tagHeight)
  }

  // MARK: Where a press begins

  /// What a press at `point` starts. The corners of the selected box come first, then the tags (the topmost box first),
  /// then the boxes (the selected one first, then the topmost); anywhere else it draws. `items` are in the order of the
  /// list, which is the stacking order.
  func begin(at point: CGPoint, items: [CanvasItem], selected: Int?) -> CanvasMode {
    guard isUsable else { return .draw }
    if let selected, let item = items.first(where: { $0.id == selected }) {
      let box = rect(of: item.box)
      for corner in CanvasCorner.allCases {
        let handle = handlePoint(corner, of: box)
        if hypot(point.x - handle.x, point.y - handle.y) <= Self.handleRadius {
          return .resize(id: item.id, corner: corner, original: item.box)
        }
      }
    }
    for item in items.reversed() where tagRect(for: item).contains(point) { return .tag(id: item.id) }
    let ordered = items.filter { $0.id == selected } + items.reversed().filter { $0.id != selected }
    for item in ordered where rect(of: item.box).contains(point) { return .move(id: item.id, original: item.box) }
    return .draw
  }

  // MARK: What a gesture makes

  /// The rectangle to show while the gesture goes on (nil for a press on a tag).
  func preview(of drag: CanvasDrag) -> GridRect? {
    switch drag.mode {
    case .draw:
      let a = grid(drag.start), b = grid(drag.current)
      return GridRect(y0: min(a.y, b.y), x0: min(a.x, b.x), y1: max(a.y, b.y), x1: max(a.x, b.x))
    case .move(_, let original):
      let box = Self.moved(original, by: delta(from: drag.start, to: drag.current))
      return GridRect(y0: Double(box.y0), x0: Double(box.x0), y1: Double(box.y1), x1: Double(box.x1))
    case .resize(_, let corner, let original):
      return resized(original, corner: corner, to: grid(drag.current))
    case .tag:
      return nil
    }
  }

  /// The box the gesture leaves, in whole numbers; nil when a drawn box is too small, or for a tag.
  func result(of drag: CanvasDrag) -> BBox? {
    switch drag.mode {
    case .draw, .resize:
      guard let area = preview(of: drag) else { return nil }
      return BBox.normalized(
        y0: Int(area.y0.rounded()), x0: Int(area.x0.rounded()), y1: Int(area.y1.rounded()), x1: Int(area.x1.rounded()))
    case .move(_, let original):
      return Self.moved(original, by: delta(from: drag.start, to: drag.current))
    case .tag:
      return nil
    }
  }

  /// `box` moved by `delta` grid units, with its size and inside the grid.
  static func moved(_ box: BBox, by delta: (dx: Double, dy: Double)) -> BBox {
    let (height, width) = (box.y1 - box.y0, box.x1 - box.x0)
    let y0 = min(max(box.y0 + Int(delta.dy.rounded()), 0), BBox.grid - height)
    let x0 = min(max(box.x0 + Int(delta.dx.rounded()), 0), BBox.grid - width)
    return BBox(y0: y0, x0: x0, y1: y0 + height, x1: x0 + width)
  }

  /// `original` with one corner at `point` and the opposite corner fixed; each side keeps at least `BBox.minSide`.
  private func resized(_ original: BBox, corner: CanvasCorner, to point: (x: Double, y: Double)) -> GridRect {
    var area = GridRect(y0: Double(original.y0), x0: Double(original.x0), y1: Double(original.y1), x1: Double(original.x1))
    let minimum = Double(BBox.minSide)
    switch corner {
    case .nw, .ne: area.y0 = min(point.y, area.y1 - minimum)
    case .sw, .se: area.y1 = max(point.y, area.y0 + minimum)
    }
    switch corner {
    case .nw, .sw: area.x0 = min(point.x, area.x1 - minimum)
    case .ne, .se: area.x1 = max(point.x, area.x0 + minimum)
    }
    return area
  }

  // MARK: The shape of the canvas

  /// The largest size with the proportions `aspect` (width / height) that fits in `available`; a nonsense aspect is a square.
  static func fit(aspect: Double, in available: CGSize) -> CGSize {
    guard available.width > 0, available.height > 0 else { return .zero }
    let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
    let byWidth = CGSize(width: available.width, height: available.width / ratio)
    if byWidth.height <= available.height { return byWidth }
    return CGSize(width: available.height * ratio, height: available.height)
  }
}

/// The size of the Generation tab, as the app says it in the `context` message (`parameters.width` and `.height`).
enum GenerationSize {
  static func read(fromContext data: Data) -> CGSize? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let parameters = object["parameters"] as? [String: Any],
      let width = parameters["width"] as? Int, let height = parameters["height"] as? Int, width > 0, height > 0
    else { return nil }
    return CGSize(width: width, height: height)
  }
}
