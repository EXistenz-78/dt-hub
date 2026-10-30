import AppKit
import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// The LoRA whose row is open, with its thumbnail large and the menu to change it; an empty card when none is open.
struct LAPreviewCard: View {
  @ObservedObject var state: LAState
  /// The thumbnail files are at most 256 pixels: this is as large as they can be shown without going soft.
  static let side: CGFloat = 176

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: state.text(.previewTitle), prominent: true)
      if let lora = state.openLoRA {
        VStack(spacing: 6) {
          LAThumbnailView(url: state.thumbnailURL(for: lora.file), side: Self.side)
          Text(verbatim: lora.name)
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.middle)
          thumbnailMenu(for: lora.file)
        }
        .frame(maxWidth: .infinity)
      } else {
        Text(verbatim: state.text(.previewEmpty))
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, minHeight: 96)
      }
    }
    .padding(DS.panelPadding)
    .frame(width: LAView.sideWidth, alignment: .topLeading)
    .dsPanel()
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
