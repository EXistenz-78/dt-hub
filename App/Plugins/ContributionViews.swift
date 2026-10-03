import HubCore
import HubKit
import SwiftUI

/// Teal at 30% behind what a plug-in filled and the user has not changed (plug-in design §7).
extension View {
  /// Highlights the row when one of `fields` holds a plug-in's value that has not been changed.
  func contributed(_ fields: [ContributionField], in store: ContributionStore?) -> some View {
    modifier(ContributedBackground(active: fields.contains { store?.marks[$0]?.isOverridden == false }))
  }

  /// Highlights the view (a LoRA, a picture) when `isContributed`.
  func contributed(_ isContributed: Bool) -> some View {
    modifier(ContributedBackground(active: isContributed))
  }
}

private struct ContributedBackground: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    content.background {
      if active {
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(DS.accent.opacity(0.3))
          .padding(.horizontal, -6)
          .padding(.vertical, -3)
      }
    }
  }
}

/// The plug-in's value kept in brackets beside the user's own: `30 (24)`.
struct ContributedReference: View {
  let field: ContributionField
  let store: ContributionStore?

  var body: some View {
    if let mark = store?.marks[field], mark.isOverridden {
      Text(verbatim: "(\(ContributionText.value(mark.value, for: field)))")
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
  }
}

/// The pop-up when two plug-ins want the same field: one button per plug-in and value. Esc leaves the
/// fields as they are.
struct ContributionConflictSheet: View {
  let plugins: PluginRegistry

  private var store: ContributionStore { plugins.contributions }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.panelPadding) {
      Text("contribution.conflict.title").font(.headline)
      Text("contribution.conflict.hint").font(.caption).foregroundStyle(.secondary)
      ForEach(store.conflicts) { conflict in
        VStack(alignment: .leading, spacing: 6) {
          Text(ContributionText.subject(conflict.subject)).font(.subheadline.weight(.semibold))
          HStack(spacing: DS.controlGap) {
            choice(conflict, side: conflict.current, proposed: false)
            choice(conflict, side: conflict.proposed, proposed: true)
          }
        }
      }
      HStack {
        Spacer()
        Button("contribution.conflict.dismiss") { store.dismissConflicts() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(DSPillButtonStyle())
      }
    }
    .padding(DS.panelPadding)
    .frame(minWidth: 420)
  }

  private func choice(_ conflict: ContributionConflict, side: ContributionConflict.Side, proposed: Bool) -> some View {
    Button {
      store.choose(conflict.id, proposed: proposed)
    } label: {
      Text(verbatim: ContributionText.choice(side, subject: conflict.subject, plugins: plugins))
        .lineLimit(1)
    }
    .buttonStyle(DSPillButtonStyle())
  }
}
