import HubCore
import HubKit
import SwiftUI

/// What the Control tab holds, in front of the eyes while on the Generation tab: the start image (Canvas) and the
/// Moodboard, two areas divided by a vertical line. Only for edit models, which work from those pictures. It does
/// nothing by itself: a click on either area opens the Control tab, and a file dropped on an area goes where it would in
/// Control (the start image, or the Moodboard).
struct InputCard: View {
  let controller: GenerationController
  /// Opens the Control tab.
  let openControl: () -> Void
  @State private var canvasTargeted = false
  @State private var moodboardTargeted = false
  @State private var problem: String?

  private var control: ControlStore { controller.control }
  /// Thumbnails shown before "+N".
  private static let visibleTiles = 4

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.input"), systemImage: "photo.on.rectangle",
      isExpanded: controller.cards.binding("input")
    ) {
      VStack(alignment: .leading, spacing: DS.controlGap) {
        HStack(alignment: .top, spacing: DS.rowGap) {
          area(title: "control.stage.title", isTargeted: canvasTargeted, expands: false) { canvasContent }
            .dropDestination(for: URL.self) { urls, _ in
              Task { problem = await ControlImport.take(urls: urls, into: control) }
              return true
            } isTargeted: { canvasTargeted = $0 }
          Divider()
          area(title: "control.moodboard.title", isTargeted: moodboardTargeted) { moodboardContent }
            .dropDestination(for: URL.self) { urls, _ in
              Task { problem = await ControlImport.takeMoodboard(urls: urls, into: control) }
              return true
            } isTargeted: { moodboardTargeted = $0 }
        }
        if let problem {
          Text(verbatim: problem).font(.caption).foregroundStyle(DS.remove).fixedSize(horizontal: false, vertical: true)
        }
      }
      .task(id: problem) {
        guard problem != nil else { return }
        try? await Task.sleep(for: .seconds(8))
        problem = nil
      }
    }
  }

  /// One side: its title over the content, all of it a button that opens Control.
  private func area<Content: View>(
    title: LocalizedStringKey, isTargeted: Bool, expands: Bool = true, @ViewBuilder content: () -> Content
  ) -> some View {
    Button(action: openControl) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        content()
      }
      // The Canvas holds one thumbnail and takes only its width; the Moodboard takes the rest.
      .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
      .padding(4)
      .contentShape(Rectangle())
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
    }
    .buttonStyle(.plain)
    .help(String(localized: "card.input.open"))
    .accessibilityHint(String(localized: "card.input.open"))
  }

  @ViewBuilder private var canvasContent: some View {
    if let image = control.inputs.image {
      InputThumbnail(request: control.previewRequest(maxPixel: 240), id: image.id)
    } else {
      placeholder(systemImage: "photo.badge.plus", width: Self.tileSize)
    }
  }

  @ViewBuilder private var moodboardContent: some View {
    let entries = control.inputs.moodboard
    if entries.isEmpty {
      placeholder(systemImage: "square.grid.2x2")
    } else {
      HStack(spacing: 6) {
        ForEach(entries.prefix(Self.visibleTiles)) { entry in
          InputThumbnail(request: control.previewRequest(ofMoodboard: entry.id, maxPixel: 240), id: entry.id)
            .opacity(entry.isOn ? 1 : 0.35)
        }
        if entries.count > Self.visibleTiles {
          Text(verbatim: "+\(entries.count - Self.visibleTiles)")
            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: 44, height: Self.tileSize)
        }
      }
    }
  }

  fileprivate static let tileSize: CGFloat = 88

  /// An empty side: the same size as a thumbnail, dashed, with the icon of what goes there.
  private func placeholder(systemImage: String, width: CGFloat? = nil) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      Image(systemName: systemImage).font(.system(size: 22)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: width ?? .infinity)
    .frame(height: Self.tileSize)
  }
}

/// A square thumbnail, decoded away from the main actor (a big PNG would stall the window).
private struct InputThumbnail: View {
  let request: PreviewRequest?
  let id: UUID
  @State private var picture: CGImage?

  var body: some View {
    Group {
      if let picture {
        Image(decorative: picture, scale: 1).resizable().scaledToFill()
      } else {
        Color.primary.opacity(0.08)
      }
    }
    .frame(width: InputCard.tileSize, height: InputCard.tileSize)
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    .task(id: id) {
      guard let request else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
  }
}
