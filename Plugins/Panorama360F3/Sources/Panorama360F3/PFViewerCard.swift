import DTHubDesign
import SwiftUI

/// The Viewer: the sphere view of the result, closed at first. It opens by itself when a panorama arrives; pictures can be dropped on it, and «Fix the seam»
/// works on the one it shows.
struct PFViewerCard: View {
  @ObservedObject var state: PFState
  let actions: PFViewActions
  @State private var dropTargeted = false

  var body: some View {
    let reason = state.seamReason
    VStack(spacing: 0) {
      DSPanelHeader(icon: "globe", title: state.text(.viewerTitle))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack(spacing: DS.controlGap) {
          Button { state.setViewerOpen(!state.doc.viewerOpen) } label: { Image(systemName: state.doc.viewerOpen ? "chevron.up" : "chevron.down") }
            .buttonStyle(DSGlassCircleButtonStyle())
          Button { actions.fixSeam() } label: { Text(state.text(.fixSeam)).lineLimit(1) }
            .buttonStyle(DSPillButtonStyle()).disabled(reason != nil || state.isSending)
            .help(reason.map { state.seamReasonText($0) } ?? "")
          Spacer(minLength: 0)
        }
        if state.doc.viewerOpen { PFSphereView(state: state) }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).stroke(DS.accent, lineWidth: dropTargeted ? 2 : 0))
    .onDrop(of: PFDrop.types, isTargeted: $dropTargeted) { providers in
      PFDrop.collect(providers, tempFolder: state.exchangeFolder) { state.dropPictures($0) }
      return true
    }
  }
}
