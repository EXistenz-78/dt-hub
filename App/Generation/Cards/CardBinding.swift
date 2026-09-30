import HubCore
import HubKit
import SwiftUI

extension CardExpansionStore {
  /// A binding for `DSCollapsibleCard`'s `isExpanded`.
  func binding(_ card: String, default defaultValue: Bool = true) -> Binding<Bool> {
    Binding(
      get: { self.isExpanded(card, default: defaultValue) },
      set: { self.setExpanded($0, for: card) })
  }
}

/// One labelled row inside a card: label on the left, an optional accessory next to it
/// (e.g. a checkbox that changes how the value is used), the control on the right.
struct CardRow<Accessory: View, Control: View>: View {
  let label: String
  @ViewBuilder let accessory: Accessory
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: DS.controlGap) {
      Text(label)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      accessory
      Spacer(minLength: DS.controlGap)
      control
    }
  }
}

extension CardRow where Accessory == EmptyView {
  init(label: String, @ViewBuilder control: () -> Control) {
    self.init(label: label, accessory: { EmptyView() }, control: control)
  }
}
