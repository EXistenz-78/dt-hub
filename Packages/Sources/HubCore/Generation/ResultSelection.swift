import Foundation

/// Which pictures of the Results strip are selected (⌘-click adds or takes away, ⇧-click extends
/// from the anchor). `primary` is the one shown large. The strip is `order`, newest first.
public struct ResultSelection: Equatable, Sendable {
  public private(set) var ids: Set<UUID> = []
  public private(set) var primary: UUID?
  public private(set) var anchor: UUID?

  public init() {}

  public init(only id: UUID?) {
    ids = id.map { [$0] } ?? []
    primary = id
    anchor = id
  }

  public mutating func click(_ id: UUID, command: Bool, shift: Bool, order: [UUID]) {
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

  public mutating func selectAll(order: [UUID]) {
    ids = Set(order)
    if primary == nil || !ids.contains(primary!) { primary = order.first }
  }

  /// Picks the nearest picture left after `removed` went: the one that took the place of the first
  /// removed (the last one if it was at the end). `order` is the strip before, `remaining` after.
  public mutating func afterRemoval(removed: Set<UUID>, order: [UUID], remaining: [UUID]) {
    let first = order.firstIndex { removed.contains($0) } ?? 0
    self = ResultSelection(only: remaining.isEmpty ? nil : remaining[min(first, remaining.count - 1)])
  }

  /// Drops what is not in the strip any more; with nothing left, the first picture.
  public mutating func keepOnly(order: [UUID]) {
    ids = ids.filter { order.contains($0) }
    if ids.isEmpty { self = ResultSelection(only: order.first); return }
    if let primary, !ids.contains(primary) { self.primary = order.first { ids.contains($0) } }
    if let anchor, !ids.contains(anchor) { self.anchor = primary }
  }
}
