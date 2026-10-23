import DTHubDesign
import SwiftUI

/// Il tab, nell'aspetto dell'app: a sinistra il Summary, a destra canvas ed elementi.
struct MossView: View {
  @ObservedObject var state: MossState
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      MossSummaryCard(state: state)
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 460, maxHeight: .infinity)
      VStack(spacing: DS.groupGap) {
        MossCanvasCard(state: state)
        MossElementsCard(state: state, send: send, write: write).frame(maxHeight: .infinity)
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
