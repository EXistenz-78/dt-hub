import SwiftUI

/// Lays its one child out at its natural width, but never wider than `maxWidth`: a text inside then truncates. A plain
/// `.frame(maxWidth:)` would let it overflow, because it passes no width to the child when it is sized by `.fixedSize()`.
struct CappedWidth: Layout {
  let maxWidth: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let child = subviews.first else { return .zero }
    let ideal = child.sizeThatFits(.unspecified).width
    let width = min(ideal, maxWidth, proposal.width ?? .infinity)
    return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }
}
