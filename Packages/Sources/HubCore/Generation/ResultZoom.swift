import CoreGraphics

/// The zoom of the large picture in the Results window: `scale` 1 is the picture fitted to the area (never less),
/// `offset` is where its centre sits from the centre of the area. Points are measured from the area's centre.
public struct ResultZoom: Equatable, Sendable {
  public static let maxScale: CGFloat = 8

  public private(set) var scale: CGFloat = 1
  public private(set) var offset: CGPoint = .zero

  public init() {}

  public var isZoomed: Bool { scale > 1 }

  public mutating func reset() { self = ResultZoom() }

  /// Multiplies the scale by `factor`, keeping the point `anchor` (from the centre of the area) under the cursor.
  /// `view` is the area, `fitted` the picture at scale 1.
  public mutating func zoom(by factor: CGFloat, at anchor: CGPoint, view: CGSize, fitted: CGSize) {
    guard factor.isFinite, factor > 0 else { return }
    let next = min(max(scale * factor, 1), Self.maxScale)
    let ratio = next / scale
    offset = CGPoint(x: anchor.x - ratio * (anchor.x - offset.x), y: anchor.y - ratio * (anchor.y - offset.y))
    scale = next
    clamp(view: view, fitted: fitted)
  }

  /// Moves the picture by `delta`, never past the edges of the area.
  public mutating func pan(by delta: CGSize, view: CGSize, fitted: CGSize) {
    offset = CGPoint(x: offset.x + delta.width, y: offset.y + delta.height)
    clamp(view: view, fitted: fitted)
  }

  /// Keeps the picture covering the area on an axis where it is larger than it; centred where it is not.
  public mutating func clamp(view: CGSize, fitted: CGSize) {
    let limitX = max(0, (fitted.width * scale - view.width) / 2)
    let limitY = max(0, (fitted.height * scale - view.height) / 2)
    offset = CGPoint(x: min(max(offset.x, -limitX), limitX), y: min(max(offset.y, -limitY), limitY))
  }
}
