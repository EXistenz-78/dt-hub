import AppKit
import DTHubDesign
import SwiftUI
import UniformTypeIdentifiers

/// The Cutout under the sphere view, on one row: the picture taken, **Extract** (the view as it is now, at the real resolution of the panorama), what can be
/// done with it (start image, Moodboard, save) and with its retouched version (put back as a sticker, or into the panorama).
struct PSCutoutPanel: View {
  @ObservedObject var state: PSState
  let actions: PSViewActions

  var body: some View {
    HStack(spacing: DS.controlGap) {
      thumbnail
      Button { extract() } label: { Text(state.text(.extract)).lineLimit(1) }.buttonStyle(DSPillButtonStyle()).fixedSize()
      iconButton("square.and.arrow.up", help: state.text(.actionStart), enabled: state.cutoutImage != nil) { actions.cutoutStart() }
      iconButton("square.grid.2x2", help: state.text(.actionMoodboard), enabled: state.cutoutImage != nil) { actions.cutoutMoodboard() }
      iconButton("square.and.arrow.down", help: state.text(.actionSave), enabled: state.cutoutImage != nil) { save() }
      Spacer().frame(width: 10)
      iconButton("mappin.and.ellipse", help: help(.actionSticker, state.putBackReason), enabled: state.putBackReason == nil) {
        state.putBackAsSticker()
      }
      iconButton("photo.badge.plus", help: help(.actionPanorama, state.putBackInPanoramaReason), enabled: state.putBackInPanoramaReason == nil && !state.isSending) {
        actions.putBackPanorama()
      }
      Spacer(minLength: 0)
    }
    .padding(DS.boxPadding)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius).fill(Color.primary.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: DS.minorRadius).stroke(Color.primary.opacity(0.15)))
  }

  @ViewBuilder private var thumbnail: some View {
    if let image = state.cutoutImage {
      Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit().frame(width: 96, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
    } else {
      RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.12)).frame(width: 96, height: 72)
    }
  }

  private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol) }.buttonStyle(DSGlassCircleButtonStyle()).help(help).disabled(!enabled)
  }

  /// The tooltip of a «put back» button: what it does, and why it is off when it is.
  private func help(_ key: L.Key, _ reason: PSCutout.PutBackReason?) -> String {
    guard let reason else { return state.text(key) }
    let why: L.Key =
      switch reason {
      case .noCutout: .putBackNoCutout
      case .noPatch: .putBackNoPatch
      case .wrongProportion: .putBackWrongProportion
      case .patchMissing: .putBackPatchMissing
      case .noPanorama: .putBackNoPanorama
      case .panoramaMissing: .putBackPanoramaMissing
      }
    return state.text(key) + " — " + state.text(why)
  }

  private func extract() {
    state.error = nil
    do { try state.extractCutout() } catch { state.error = state.text(.sendFailed) }
  }

  private func save() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "panorama-360-cutout.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try state.saveCutout(to: url) } catch { state.error = state.text(.sendFailed) }
  }
}
