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
/// (e.g. a checkbox that changes how the value is used), the control on the right. A row for fields
/// a plug-in can fill (`fields`) turns teal while a plug-in's value is in it, and shows that value in
/// brackets once the user has changed it (plug-in design §7).
struct CardRow<Accessory: View, Control: View>: View {
  let label: String
  var fields: [ContributionField] = []
  @ViewBuilder let accessory: Accessory
  @ViewBuilder let control: Control
  @Environment(ContributionStore.self) private var contributions: ContributionStore?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      Text(label)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      accessory
      Spacer(minLength: DS.controlGap)
      if let first = fields.first(where: { contributions?.marks[$0]?.isOverridden == true }) {
        ContributedReference(field: first, store: contributions)
      }
      control
    }
    .contributed(fields, in: contributions)
  }
}

extension CardRow where Accessory == EmptyView {
  init(label: String, fields: [ContributionField] = [], @ViewBuilder control: () -> Control) {
    self.init(label: label, fields: fields, accessory: { EmptyView() }, control: control)
  }
}
