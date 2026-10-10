import CoreGraphics
import Foundation

/// The shape of a mark, the one place that says where it goes: the screen and the PNG both draw from it.
enum MarkGeometry {
  /// Half the opening of the head of an arrow.
  static let headHalfAngle = 25.0 * Double.pi / 180

  /// `stroke` is drawn with `lineWidth` (round caps and joins); `fill` (the head of an arrow) is filled. The coordinates are
  /// those of `size`; `lineWidth` is the mark's width in pixels of the image, scaled to `size`.
  static func paths(
    for mark: Mark, in size: CGSize, imageWidth: Double
  ) -> (stroke: CGPath, fill: CGPath?, lineWidth: CGFloat) {
    let lineWidth = CGFloat(mark.width * size.width / max(imageWidth, 1))
    let points = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    switch mark.tool {
    case .box, .circle:
      guard points.count >= 2 else { return (CGMutablePath(), nil, lineWidth) }
      let rect = CGRect(
        x: min(points[0].x, points[1].x), y: min(points[0].y, points[1].y), width: abs(points[1].x - points[0].x),
        height: abs(points[1].y - points[0].y))
      return (mark.tool == .box ? CGPath(rect: rect, transform: nil) : CGPath(ellipseIn: rect, transform: nil), nil, lineWidth)
    case .arrow:
      guard points.count >= 2 else { return (CGMutablePath(), nil, lineWidth) }
      return arrow(from: points[0], to: points[1], lineWidth: lineWidth)
    case .sketch:
      return (sketch(points), nil, lineWidth)
    }
  }

  private static func arrow(from tail: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> (CGPath, CGPath?, CGFloat) {
    let length = hypot(tip.x - tail.x, tip.y - tail.y)
    let shaft = CGMutablePath()
    guard length > 0 else {
      shaft.move(to: tail)
      shaft.addLine(to: tail)
      return (shaft, nil, lineWidth)
    }
    let head = min(max(lineWidth * 4, 12), length * 2 / 3)
    let ux = (tip.x - tail.x) / length
    let uy = (tip.y - tail.y) / length
    let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
    let half = head * CGFloat(tan(headHalfAngle))
    shaft.move(to: tail)
    shaft.addLine(to: base)
    let triangle = CGMutablePath()
    triangle.move(to: tip)
    triangle.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
    triangle.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
    triangle.closeSubpath()
    return (shaft, triangle, lineWidth)
  }

  /// A smooth curve: each original point is the control of a quadratic between the midpoints, then a line to the last point.
  private static func sketch(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    if points.count == 1 {
      path.addLine(to: first)  // a dot, with round caps
    } else if points.count == 2 {
      path.addLine(to: points[1])
    } else {
      path.addLine(to: mid(points[0], points[1]))
      for index in 1..<(points.count - 1) {
        path.addQuadCurve(to: mid(points[index], points[index + 1]), control: points[index])
      }
      path.addLine(to: points[points.count - 1])
    }
    return path
  }

  private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
}
