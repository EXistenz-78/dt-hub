import AppKit
import DTHubDesign
import SwiftUI

/// La finestra con il JSON: un testo che chiunque può copiare e cambiare a mano. Se è cambiato, è quello che parte con «Invia».
struct MossReviewSheet: View {
  @ObservedObject var state: MossState
  let close: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "doc.text", title: L.text(.reviewJSON, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        JSONEditor(text: Binding(get: { state.jsonText }, set: { state.editJSON($0) }))
          .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
          .frame(minHeight: 360)
        HStack(spacing: DS.controlGap) {
          if state.hasEditedJSON { Text(L.text(.reviewNote, italian: state.italian)).font(.caption).foregroundStyle(DS.remove) }
          Spacer(minLength: 0)
          Button(L.text(.copy, italian: state.italian)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.jsonText, forType: .string)
          }
          .buttonStyle(DSPillButtonStyle())
          Button(L.text(.restoreFromFields, italian: state.italian)) { state.restoreJSON() }
            .buttonStyle(DSPillButtonStyle()).disabled(!state.hasEditedJSON)
          Button(L.text(.close, italian: state.italian), action: close).buttonStyle(DSPillButtonStyle(prominent: true))
        }
      }
      .padding(DS.panelPadding)
    }
    .frame(minWidth: 640, minHeight: 480)
  }
}
