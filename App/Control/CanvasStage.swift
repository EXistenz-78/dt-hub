import HubCore
import HubKit
import SwiftUI

/// The canvas as Draw Things will get it (spec: tab Control §3, §5): the start image with the
/// part that is cut off darkened. Dragging moves the cut along the axis that is cropped.
struct CanvasStage: View {
  let generation: GenerationController
  @State private var picture: CGImage?
  @State private var dragStart: Framing?

  private var control: ControlStore { generation.control }
  private var canvasWidth: Int { generation.parameters.width }
  private var canvasHeight: Int { generation.parameters.height }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.stage.title"), systemImage: "rectangle.dashed",
      isExpanded: generation.cards.binding("control.stage")
    ) {
      VStack(spacing: DS.rowGap) {
        if let image = control.inputs.image {
          stage(for: image)
          caption(for: image)
        } else {
          empty
        }
      }
    }
    .task(id: control.inputs.image?.id) {
      guard let request = control.previewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
  }

  private var empty: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      Text("control.stage.empty").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        .padding()
    }
    .aspectRatio(Double(canvasWidth) / Double(max(canvasHeight, 1)), contentMode: .fit)
    .frame(maxHeight: 300)
  }

  private func stage(for image: ReferenceImage) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      let crop = FramingMath.cropRect(
        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
        canvasHeight: canvasHeight, framing: control.inputs.framing)
      let rect = CGRect(
        x: crop.minX / Double(image.pixelWidth) * size.width, y: crop.minY / Double(image.pixelHeight) * size.height,
        width: crop.width / Double(image.pixelWidth) * size.width,
        height: crop.height / Double(image.pixelHeight) * size.height)
      ZStack {
        if let picture {
          Image(decorative: picture, scale: 1).resizable().interpolation(.high)
        } else {
          Color.primary.opacity(0.08)
        }
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          path.addRect(rect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
      }
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let start = dragStart ?? control.inputs.framing
            dragStart = start
            move(from: start, by: value.translation, in: size, image: image, crop: crop)
          }
          .onEnded { _ in dragStart = nil })
    }
    .aspectRatio(Double(image.pixelWidth) / Double(max(image.pixelHeight, 1)), contentMode: .fit)
    .frame(maxHeight: 340)
  }

  /// The cut follows the pointer along the cropped axis; the other axis has nothing to move.
  private func move(from start: Framing, by translation: CGSize, in size: CGSize, image: ReferenceImage, crop: CGRect) {
    let slackX = Double(image.pixelWidth) - crop.width
    let slackY = Double(image.pixelHeight) - crop.height
    var x = start.offsetX
    var y = start.offsetY
    if slackX > 0.5 {
      x += translation.width * (Double(image.pixelWidth) / size.width) / (slackX / 2)
    }
    if slackY > 0.5 {
      y += translation.height * (Double(image.pixelHeight) / size.height) / (slackY / 2)
    }
    control.setOffset(x: x, y: y)
  }

  @ViewBuilder private func caption(for image: ReferenceImage) -> some View {
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
    VStack(alignment: .leading, spacing: 2) {
      Text(
        String(
          format: String(localized: "control.stage.size"), canvasWidth, canvasHeight)
      )
      .font(.caption).foregroundStyle(.secondary)
      if let axis = loss.axis {
        Text(
          String(
            format: String(localized: axis == .vertical ? "control.stage.loss.vertical" : "control.stage.loss.horizontal"),
            Int((loss.fraction * 100).rounded()))
        )
        .font(.caption).foregroundStyle(.secondary)
        Text("control.stage.drag").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
