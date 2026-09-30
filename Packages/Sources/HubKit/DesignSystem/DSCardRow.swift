import SwiftUI

/// Cards side by side with the same width and the exact same height: that of the tallest
/// card (spec §7). Each card fills the height the row settles on.
public struct DSCardRow<Content: View>: View {
  let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    // The row takes its ideal height, the tallest card's; every card then fills it.
    .fixedSize(horizontal: false, vertical: true)
  }
}
