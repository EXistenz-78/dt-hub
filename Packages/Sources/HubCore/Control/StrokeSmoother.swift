import CoreGraphics
import Foundation

/// Turns the few points a mouse gives into a smooth stroke: the stroke passes through the middles
/// of the segments and bends toward the points between them (a quadratic curve for each pair), so a
/// slow frame rate does not show as corners. The curve is a little behind the pointer, and
/// `finish` takes it to the last point.
public struct StrokeSmoother: Equatable, Sendable {
  private var last: CGPoint?
  private var lastMid: CGPoint?

  public init() {}

  /// True from the first point to `finish`.
  public var isActive: Bool { last != nil }

  /// Adds a point; returns the points to join with straight segments, the first one where the
  /// stroke was (a point alone for the very first). `spacing` is about how far apart the points
  /// of a curve are, in the same pixels as the points.
  public mutating func add(_ point: CGPoint, spacing: Double) -> [CGPoint] {
    guard let previous = last, let from = lastMid else {
      last = point
      lastMid = point
      return [point]
    }
    let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
    last = point
    lastMid = mid
    let chord = hypot(previous.x - from.x, previous.y - from.y) + hypot(mid.x - previous.x, mid.y - previous.y)
    let steps = min(64, max(1, Int((chord / max(spacing, 0.5)).rounded(.up))))
    var points = [from]
    for step in 1...steps {
      let t = Double(step) / Double(steps)
      let a = (1 - t) * (1 - t)
      let b = 2 * (1 - t) * t
      let c = t * t
      points.append(CGPoint(x: a * from.x + b * previous.x + c * mid.x, y: a * from.y + b * previous.y + c * mid.y))
    }
    return points
  }

  /// Ends the stroke: the points from where it was to the last point added.
  public mutating func finish() -> [CGPoint] {
    defer {
      last = nil
      lastMid = nil
    }
    guard let last, let lastMid else { return [] }
    return last == lastMid ? [last] : [lastMid, last]
  }
}
