import AppKit
import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// The LoRA whose row is open, with its thumbnail large and the menu to change it; an empty card when none is open.
struct LAPreviewCard: View {
  @ObservedObject var state: LAState
  /// As wide as the text box of the advice card below.
  static let side: CGFloat = LAView.sideWidth - 2 * DS.panelPadding

  var body: some View {
    // No LoRA open, no card: the advice card takes the column.
    if let lora = state.openLoRA {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        DSGroupHeader(title: lora.name, prominent: true)
        VStack(spacing: 6) {
          LAThumbnailView(url: state.thumbnailURL(for: lora.file), side: Self.side)
          thumbnailMenu(for: lora.file)
        }
        .frame(maxWidth: .infinity)
        LAWeightFields(state: state, lora: lora)
      }
      .padding(DS.panelPadding)
      .frame(width: LAView.sideWidth, alignment: .topLeading)
      .dsPanel()
    }
  }

  /// A picture of the user's own for the thumbnail: a file, or the start image of the Control tab.
  private func thumbnailMenu(for file: String) -> some View {
    Menu(state.text(.thumbnail)) {
      Button(state.text(.chooseFile)) { chooseFile(for: file) }
      Button(state.text(.useControlImage)) { state.useControlImage(for: file) }
        .disabled(!state.canUseControlImage)
      Button(state.text(.removeThumbnail)) { state.removeThumbnail(for: file) }
        .disabled(state.entry(for: file).thumbnail == nil)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  private func chooseFile(for file: String) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .webP, .heic]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    state.setThumbnail(fromFile: url, for: file)
  }
}
