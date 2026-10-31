import Foundation

/// Which pictures of the Results strip are selected (⌘-click adds or takes away, ⇧-click extends
/// from the anchor). `primary` is the one shown large. The strip is `order`, newest first.
public struct ResultSelection<ID: Hashable & Sendable>: Equatable, Sendable {
  public private(set) var ids: Set<ID> = []
  public private(set) var primary: ID?
  public private(set) var anchor: ID?

  public init() {}

  public init(only id: ID?) {
    ids = id.map { [$0] } ?? []
    primary = id
    anchor = id
  }

  public mutating func click(_ id: ID, command: Bool, shift: Bool, order: [ID]) {
    if command {
      if ids.contains(id) {
        // The last picture selected stays: something is always chosen.
        guard ids.count > 1 else { return }
        ids.remove(id)
        if primary == id { primary = order.first { ids.contains($0) } }
      } else {
        ids.insert(id)
        primary = id
      }
      anchor = id
    } else if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
      ids = Set(order[min(from, to)...max(from, to)])
      primary = id
    } else {
      self = ResultSelection(only: id)
    }
  }

  /// The arrow keys: selects only the picture `delta` places along `order` from the shown one (the first when
  /// nothing is shown), and stops at the ends.
  public mutating func step(_ delta: Int, order: [ID]) {
    guard !order.isEmpty else { return }
    let current = primary.flatMap { order.firstIndex(of: $0) }
    let target = current.map { min(max($0 + delta, 0), order.count - 1) } ?? 0
    self = ResultSelection(only: order[target])
  }

  public mutating func selectAll(order: [ID]) {
    ids = Set(order)
    if primary == nil || !ids.contains(primary!) { primary = order.first }
  }

  /// Picks the nearest picture left after `removed` went: the one that took the place of the first
  /// removed (the last one if it was at the end). `order` is the strip before, `remaining` after.
  public mutating func afterRemoval(removed: Set<ID>, order: [ID], remaining: [ID]) {
    let first = order.firstIndex { removed.contains($0) } ?? 0
    self = ResultSelection(only: remaining.isEmpty ? nil : remaining[min(first, remaining.count - 1)])
  }

  /// Drops what is not in the strip any more; with nothing left, the first picture.
  public mutating func keepOnly(order: [ID]) {
    ids = ids.filter { order.contains($0) }
    if ids.isEmpty { self = ResultSelection(only: order.first); return }
    if let primary, !ids.contains(primary) { self.primary = order.first { ids.contains($0) } }
    if let anchor, !ids.contains(anchor) { self.anchor = primary }
  }
}
