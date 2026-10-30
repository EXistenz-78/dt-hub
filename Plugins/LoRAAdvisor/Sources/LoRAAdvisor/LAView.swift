import AppKit
import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// The tab, in the look of the app: the list of the LoRAs on the left, wide; the advice on the right, narrow.
struct LAView: View {
  @ObservedObject var state: LAState
  /// The width of the advice card: fixed, as the side card of Batch plus.
  static let sideWidth: CGFloat = 320

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      LAListCard(state: state)
        .frame(maxWidth: .infinity)
      VStack(spacing: DS.groupGap) {
        LAPreviewCard(state: state)
        LAAdviceCard(state: state)
      }
      .frame(width: LAView.sideWidth)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// A LoRA's thumbnail, or a dashed box when it has none.
struct LAThumbnailView: View {
  let url: URL?
  let side: CGFloat

  var body: some View {
    Group {
      if let image = url.flatMap(Self.image) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }

  /// The pictures are small files with names that never repeat: read once, kept by path.
  private static let cache = NSCache<NSString, NSImage>()

  private static func image(_ url: URL) -> NSImage? {
    if let cached = cache.object(forKey: url.path as NSString) { return cached }
    guard let image = NSImage(contentsOf: url) else { return nil }
    cache.setObject(image, forKey: url.path as NSString)
    return image
  }
}

/// A small coloured word beside a LoRA: where its page stands, or that it is on the Generation tab already.
struct LATag: View {
  let text: String
  var warning = false

  var body: some View {
    Text(verbatim: text)
      .font(.caption)
      .foregroundStyle(warning ? DS.remove : DS.accent)
      .lineLimit(1)
  }
}
