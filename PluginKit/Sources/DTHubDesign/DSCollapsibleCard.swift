import SwiftUI

/// A collapsible card of the Generation tab (spec §7). `tint` colours the card, e.g.
/// `DS.remove` for the negative prompt. A custom disclosure rather than `DisclosureGroup`:
/// the stock control keeps a system focus ring around its triangle. Pass a localized title
/// (`String(localized:)`): the catalog test rejects literals here. `trailing` is an optional accessory at the
/// right of the title (a "remove" button, say); it is not part of the button that opens and closes the card.
public struct DSCollapsibleCard<Content: View, Trailing: View>: View {
  let title: String
  let systemImage: String?
  let tint: Color?
  @Binding var isExpanded: Bool
  let trailing: Trailing
  let content: Content

  public init(
    _ title: String,
    systemImage: String? = nil,
    tint: Color? = nil,
    isExpanded: Binding<Bool>,
    @ViewBuilder trailing: () -> Trailing,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    self._isExpanded = isExpanded
    self.trailing = trailing()
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if isExpanded {
        content
          .padding([.horizontal, .bottom], DS.panelPadding)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    // Fills the height it is offered, so cards side by side can share one height (`DSCardRow`).
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(
      (tint ?? Color.clear).opacity(0.12),
      in: RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous)
    )
    .dsPanel()
  }

  /// Without an accessory the whole header row, padding included, is the button, as it always was.
  private var hasAccessory: Bool { Trailing.self != EmptyView.self }

  private var header: some View {
    HStack(spacing: DS.controlGap) {
      toggleButton
      if hasAccessory {
        trailing
          .padding(.trailing, DS.panelPadding)
      }
    }
  }

  private var toggleButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .bold))
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .accessibilityHidden(true)
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint ?? Color.secondary)
        }
        DSGroupHeader(title: title, prominent: true)
        Spacer(minLength: 0)
      }
      // The padding is inside the button: the margins around the title open and close the card too.
      .padding(.leading, DS.panelPadding)
      .padding(.trailing, hasAccessory ? 0 : DS.panelPadding)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Reachable with the keyboard; only the system focus ring is hidden.
    .focusEffectDisabled()
    .accessibilityAddTraits(.isHeader)
  }
}

extension DSCollapsibleCard where Trailing == EmptyView {
  /// A card without an accessory.
  public init(
    _ title: String,
    systemImage: String? = nil,
    tint: Color? = nil,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      title, systemImage: systemImage, tint: tint, isExpanded: isExpanded, trailing: { EmptyView() },
      content: content)
  }
}

#Preview("Cards") {
  @Previewable @State var promptOpen = true
  @Previewable @State var negativeOpen = true
  VStack(spacing: DS.groupGap) {
    DSCollapsibleCard("Prompt", systemImage: "text.cursor", isExpanded: $promptOpen) {
      Text("A stone farmhouse in a field at noon")
    }
    DSCollapsibleCard("Negative", systemImage: "minus.circle", tint: DS.remove, isExpanded: $negativeOpen) {
      Text("blurry, lowres")
    }
  }
  .padding(20)
  .frame(width: 520)
  .background(DSBackground())
}
