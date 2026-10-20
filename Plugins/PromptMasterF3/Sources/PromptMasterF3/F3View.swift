import DTHubDesign
import SwiftUI

/// Il tab, nell'aspetto dell'app: a sinistra descrizione e composizione, a destra canvas ed elementi.
struct F3View: View {
  @ObservedObject var state: F3State
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      VStack(spacing: DS.groupGap) {
        F3DescriptionCard(state: state).frame(maxHeight: .infinity)
        F3CompositionCard(state: state)
      }
      .frame(minWidth: 340, idealWidth: 420, maxWidth: 460)
      VStack(spacing: DS.groupGap) {
        F3CanvasCard(state: state)
        F3ElementsCard(state: state, send: send, write: write).frame(maxHeight: .infinity)
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
