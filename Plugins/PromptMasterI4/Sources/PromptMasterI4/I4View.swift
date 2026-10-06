import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the lists and the text on the left, the elements and the buttons on the right.
struct I4View: View {
  @ObservedObject var state: I4State
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      I4LeftCard(state: state).frame(minWidth: 340, idealWidth: 420, maxWidth: 460)
      VStack(spacing: DS.groupGap) {
        I4CanvasCard(state: state)
        I4ElementsCard(state: state, send: send, write: write).frame(maxHeight: .infinity)
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
