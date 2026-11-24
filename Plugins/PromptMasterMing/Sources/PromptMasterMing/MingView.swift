import DTHubDesign
import SwiftUI

/// Il tab, nell'aspetto dell'app: a sinistra le impostazioni della tela, a destra canvas e livelli.
struct MingView: View {
  @ObservedObject var state: MingState
  let send: () -> Void
  let write: () -> Void
  let compose: () -> Void
  let importPrompt: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      MingSummaryCard(state: state, compose: compose)
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 460, maxHeight: .infinity)
      VStack(spacing: DS.groupGap) {
        MingCanvasCard(state: state, importPrompt: importPrompt)
        MingLayersCard(state: state, send: send, write: write, importPrompt: importPrompt).frame(maxHeight: .infinity)
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
