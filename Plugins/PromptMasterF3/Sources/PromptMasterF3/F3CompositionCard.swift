import DTHubDesign
import SwiftUI

/// La card 2, il più compatta possibile: la casella di testo, la didascalia e, solo quando serve, l'avviso dell'id ripetuto.
struct F3CompositionCard: View {
  @ObservedObject var state: F3State

  private var colors: [String: Int] { Dictionary(state.document.elements.map { ($0.id, $0.colorIndex) }, uniquingKeysWith: { a, _ in a }) }

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.badge.plus", title: "2 · " + L.text(.compositionTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: 6) {
        ZStack(alignment: .topLeading) {
          F3CompositionEditor(
            text: Binding(get: { state.document.composition }, set: { _ in }), colors: colors,
            placeholder: L.text(.compositionPlaceholder, italian: state.italian),
            onChange: { state.compositionChanged($0) }, onCommit: { state.commitComposition() })
          if state.document.composition.isEmpty {
            Text(L.text(.compositionPlaceholder, italian: state.italian)).foregroundStyle(.tertiary).font(.callout)
              .padding(.horizontal, 8).padding(.vertical, 6).allowsHitTesting(false)
          }
        }
        .frame(height: 70)
        .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
        Text(L.text(.compositionHint, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        ForEach(state.duplicateIDs, id: \.self) { id in
          Text("⚠ " + L.format(.duplicateWarning, "<\(id)>", F3IDParser.numberingBase(of: id), F3IDParser.numberingBase(of: id), italian: state.italian))
            .font(.caption).foregroundStyle(DS.remove)
        }
      }
      .padding(.horizontal, DS.panelPadding).padding(.vertical, 10)
    }
    .dsPanel()
  }
}
