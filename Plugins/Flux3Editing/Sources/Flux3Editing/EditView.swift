import DTHubDesign
import SwiftUI

/// Il tab, nell'aspetto dell'app: il Moodboard e l'immagine di partenza affiancati, sotto il Prompt.
struct EditView: View {
  @ObservedObject var state: EditState
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        HStack(alignment: .top, spacing: DS.groupGap) {
          MoodboardCard(state: state).frame(maxWidth: .infinity)
          StartImageCard(state: state).frame(maxWidth: .infinity)
        }
        PromptCard(state: state, send: send, write: write)
      }
      .padding(DS.groupGap)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
