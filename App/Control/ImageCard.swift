import HubCore
import HubKit
import SwiftUI

/// The start image (spec: tab Control §3): thumbnail with its origin, replace and remove, a drop
/// zone, adapt the dimensions, and the strength.
struct ImageCard: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  /// Reports what went wrong with an import, or that the dimensions were adapted.
  let report: (ControlMessage) -> Void
  @State private var thumbnail: CGImage?
  @State private var isTargeted = false
  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
  @Environment(ContributionStore.self) private var contributions: ContributionStore?

  private var control: ControlStore { generation.control }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.image.title"), systemImage: "photo",
      isExpanded: generation.cards.binding("control.image")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let image = control.inputs.image {
          loaded(image).contributed(contributions?.startImage?.id == image.id)
          strengthRow
        } else {
          emptyZone
        }
      }
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
      .dropDestination(for: URL.self) { urls, _ in
        Task { if let message = await ControlImport.take(urls: urls, into: control) { report(.error(message)) } }
        return true
      } isTargeted: { isTargeted = $0 }
    }
    .task(id: control.inputs.image?.id) {
      // Decoded away from the main actor: a big PNG would stall the window.
      guard let request = control.previewRequest(maxPixel: 240) else { return thumbnail = nil }
      thumbnail = await Task.detached { request.render() }.value
    }
  }

  private func loaded(_ image: ReferenceImage) -> some View {
    HStack(alignment: .top, spacing: DS.rowGap) {
      ZStack(alignment: .topTrailing) {
        Group {
          if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
          } else {
            Color.primary.opacity(0.08)
          }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        .modifier(DragOut(url: control.copyURL(of: image)))
        Button {
          control.removeImage()
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(String(localized: "control.image.remove"))
        .help(String(localized: "control.image.remove"))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: image.name).font(.callout.weight(.semibold)).lineLimit(2)
        Text(
          String(
            format: String(localized: "control.image.info"), image.pixelWidth, image.pixelHeight,
            ControlText.source(image.source, plugins: plugins))
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: DS.controlGap) {
          Button("control.image.replace") {
            Task { if let message = await ControlImport.choose(into: control) { report(.error(message)) } }
          }
          .buttonStyle(DSPillButtonStyle())
          Button("control.image.adapt") {
            if let previous = generation.adaptDimensionsToImage() { report(.adapted(previous)) }
          }
          .buttonStyle(DSPillButtonStyle())
          .help(String(localized: "control.image.adapt.help"))
        }
        .padding(.top, 4)
      }
    }
  }

  private var emptyZone: some View {
    VStack(spacing: DS.controlGap) {
      Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
      Text("control.image.drop").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("control.image.choose") {
        Task { if let message = await ControlImport.choose(into: control) { report(.error(message)) } }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
  }

  private var strengthRow: some View {
    let edit = generation.isEditModel(in: connection)
    let margins = control.hasMargins(canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)
    let value = control.inputs.effectiveStrength(editModel: edit, hasMargins: margins)
    return VStack(alignment: .leading, spacing: 4) {
      CardRow(label: String(localized: "control.strength")) {
        Slider(
          value: Binding(get: { value }, set: { control.setStrength($0) }), in: 0...1, step: 0.01
        )
        .frame(minWidth: 120)
      } control: {
        IntField(
          label: String(localized: "control.strength"),
          value: Binding(get: { Int((value * 100).rounded()) }, set: { control.setStrength(Double($0) / 100) }),
          range: 0...100, step: 5, commit: { $0 })
      }
      HStack(spacing: DS.controlGap) {
        if edit {
          Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
        } else if control.inputs.mask != nil || margins, control.inputs.strength == nil {
          Text("control.strength.mask").font(.caption).foregroundStyle(.secondary)
        }
        if control.inputs.strength != nil {
          Button("control.strength.auto") { control.setStrength(nil) }
            .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
        }
      }
    }
  }
}

/// A line of the Control tab's message bar.
enum ControlMessage: Equatable {
  case error(String)
  /// The dimensions were adapted; the previous ones can be put back.
  case adapted(Size)
}

/// The thumbnail can be dragged out as the file of its copy (into the Moodboard, or another app).
private struct DragOut: ViewModifier {
  let url: URL?

  func body(content: Content) -> some View {
    if let url { content.draggable(url) } else { content }
  }
}
