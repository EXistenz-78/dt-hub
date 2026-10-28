import AppKit
import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The Cutout, on the header of the Viewer: the size in megapixels, **Extract** (the view as it is now, as a flat 4:3 picture) and what can be done with it
/// (start image, Moodboard, save) and with its retouched version (put it back in the panorama). The same buttons as in Panorama 360.
struct PFCutoutControls: View {
  @ObservedObject var state: PFState
  let actions: PFViewActions

  private var size: (width: Int, height: Int) { PFCutout.size(megapixels: state.doc.cutoutMegapixels) }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      thumbnail
      TextField(
        "",
        value: Binding(
          get: { state.doc.cutoutMegapixels },
          set: { value in state.mutate { $0.cutoutMegapixels = min(PFCutout.megapixelRange.upperBound, max(PFCutout.megapixelRange.lowerBound, value)) } }),
        format: .number.precision(.fractionLength(0...2))
      )
      .textFieldStyle(.roundedBorder).font(.body.monospaced()).frame(width: 56)
      Text(state.text(.megapixels)).font(.caption).foregroundStyle(.secondary)
        .help("\(size.width) × \(size.height) px")
      Button(state.text(.extract)) { extract() }.buttonStyle(DSPillButtonStyle()).disabled(state.resultImage == nil)
      iconButton("square.and.arrow.up", help: state.text(.actionStart), enabled: state.cutoutImage != nil) { actions.cutoutStart() }
      iconButton("square.grid.2x2", help: state.text(.actionMoodboard), enabled: state.cutoutImage != nil) { actions.cutoutMoodboard() }
      iconButton("square.and.arrow.down", help: state.text(.actionSave), enabled: state.cutoutImage != nil) { save() }
      iconButton("photo.badge.plus", help: help(), enabled: state.putBackInPanoramaReason == nil && !state.isSending) { actions.putBackPanorama() }
    }
  }

  @ViewBuilder private var thumbnail: some View {
    if let image = state.cutoutImage {
      Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 48, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
    } else {
      RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)).frame(width: 48, height: 36)
    }
  }

  private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }.buttonStyle(DSGlassCircleButtonStyle()).help(help).disabled(!enabled)
  }

  /// The tooltip of «put back»: what it does, and why it is off when it is.
  private func help() -> String {
    guard let reason = state.putBackInPanoramaReason else { return state.text(.actionPanorama) }
    return state.text(.actionPanorama) + " — " + state.putBackText(reason)
  }

  private func extract() {
    state.error = nil
    do { try state.extractCutout() } catch { state.error = state.text(.cutoutNothing) }
  }

  private func save() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "pano-360-f3-cutout.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try state.saveCutout(to: url) } catch { state.error = state.text(.sendFailed) }
  }
}
