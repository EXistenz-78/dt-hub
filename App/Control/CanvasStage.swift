import AppKit
import HubCore
import HubKit
import SwiftUI

/// The canvas (spec: tab Control §3, §5), in two modes. **Canvas** shows the start image with the
/// part that is cut off darkened; dragging moves the cut along the axis that is cropped. **Draw**
/// shows the canvas as Draw Things will get it, with the tools: Mask + (paints the area to
/// regenerate, in orange), Mask − (takes it away) and Brush (draws in colour on the image).
/// Each stroke is one step of the tab's history (⌘Z).
struct CanvasStage: View {
  let generation: GenerationController
  /// Reports what went wrong while drawing.
  let report: (ControlMessage) -> Void

  private enum Mode: Hashable {
    case canvas, draw
  }

  @State private var picture: CGImage?
  @State private var mode = Mode.canvas
  @State private var tool = DrawingTool.maskAdd
  @State private var dragStart: Framing?
  /// The mask and the drawing while they are drawn (the images are updated in place).
  @State private var drawing = CanvasDrawing()
  @State private var hover: CGPoint?
  @State private var brushColor = Color.red
  @State private var brushRGB: (red: UInt8, green: UInt8, blue: UInt8) = (255, 59, 48)
  /// The tools' diameter in canvas pixels.
  @AppStorage("control.brushSize") private var brushSize = 96.0

  /// The height of the tab's window: the pictures grow with it.
  @Environment(\.controlViewportHeight) private var viewportHeight

  private var control: ControlStore { generation.control }
  private var canvasWidth: Int { generation.parameters.width }
  private var canvasHeight: Int { generation.parameters.height }
  /// What the drawing was read from: when it changes (undo, redo, clear, a new image) it is read again.
  private var key: [String?] {
    [control.inputs.image?.id.uuidString, control.inputs.mask?.fileName, control.inputs.paint?.fileName]
  }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.stage.title"), systemImage: "rectangle.dashed",
      isExpanded: generation.cards.binding("control.stage")
    ) {
      VStack(spacing: DS.rowGap) {
        if let image = control.inputs.image {
          modePicker
          if mode == .draw { tools }
          if mode == .canvas {
            stage(for: image)
            caption(for: image)
          } else {
            drawArea(for: image)
            if tool != .brush || control.inputs.mask != nil { maskSettings }
          }
        } else {
          empty
        }
      }
    }
    .task(id: control.inputs.image?.id) {
      guard let request = control.previewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
    .task(id: key) { drawing.sync(with: control) }
    .onChange(of: brushColor) { brushRGB = rgb(of: brushColor) }
  }

  /// The two modes, as wide as the card: the top of the card's hierarchy.
  private var modePicker: some View {
    HStack(spacing: 2) {
      modeButton("control.stage.mode.canvas", .canvas)
      modeButton("control.stage.mode.draw", .draw)
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
  }

  private func modeButton(_ label: LocalizedStringResource, _ value: Mode) -> some View {
    Button {
      mode = value
    } label: {
      Text(label).font(.callout.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(mode == value ? DS.accent : Color.clear))
        .foregroundStyle(mode == value ? Color.white : Color.primary)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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

  // MARK: Canvas mode

  /// A picture area of the given ratio as large as the card and the window allow, centered: a
  /// rectangle that takes the card's width (up to what the window's height allows for this ratio) and
  /// puts the content over it.
  private func sized<Content: View>(ratio: Double, @ViewBuilder content: () -> Content) -> some View {
    let tallest = max(340, viewportHeight - 330)
    return Color.clear
      .aspectRatio(ratio, contentMode: .fit)
      .frame(maxWidth: tallest * ratio)
      .overlay { content() }
      .frame(maxWidth: .infinity)
  }

  private func stage(for image: ReferenceImage) -> some View {
    sized(ratio: Double(image.pixelWidth) / Double(max(image.pixelHeight, 1))) {
      stageContent(for: image)
    }
  }

  private func stageContent(for image: ReferenceImage) -> some View {
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
        if let paintImage = drawing.paintImage { Image(decorative: paintImage, scale: 1).resizable().interpolation(.high) }
        if let maskImage = drawing.maskImage { Image(decorative: maskImage, scale: 1).resizable().interpolation(.high) }
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
        .font(.caption).foregroundStyle(loss.fraction > 1.0 / 3.0 ? DS.remove : .secondary)
        Text("control.stage.drag").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Draw mode: tools

  /// One row like a toolbar: the tools, then what belongs to the tool chosen (invert and clear for the
  /// mask, the colour and clear for the Brush), and Undo and Redo at the end. Icons only: the names
  /// are in the tooltips.
  private var tools: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        HStack(spacing: 2) {
          toolButton("eraser", badge: "plus", "control.tool.maskAdd", .maskAdd)
          toolButton("eraser", badge: "minus", "control.tool.maskRemove", .maskRemove)
          toolButton("paintbrush.pointed", badge: nil, "control.tool.brush", .brush)
        }
        Divider().frame(height: 18)
        if tool == .brush {
          ColorPicker(String(localized: "control.brush.color"), selection: $brushColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44)
            .help(String(localized: "control.brush.color"))
          iconButton("trash", "control.paint.clear", tint: DS.remove, enabled: control.inputs.paint != nil) {
            control.clearPaint()
          }
        } else {
          iconButton("circle.lefthalf.filled", "control.mask.invert") {
            attempt { () throws(ControlError) in try control.invertMask() }
          }
          iconButton("trash", "control.mask.clear", tint: DS.remove, enabled: control.inputs.mask != nil) {
            control.clearMask()
          }
        }
        Spacer(minLength: 0)
        iconButton("arrow.uturn.backward", "control.undo", enabled: control.canUndo) { control.undo() }
        iconButton("arrow.uturn.forward", "control.redo", enabled: control.canRedo) { control.redo() }
      }
      CardRow(label: String(localized: "control.mask.size")) {
        Slider(value: $brushSize, in: 8...512, step: 1).frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(Int(brushSize)) px").font(.callout).monospacedDigit().foregroundStyle(.secondary)
          .frame(width: 64, alignment: .trailing)
      }
    }
  }

  private func toolButton(
    _ systemImage: String, badge: String?, _ label: LocalizedStringResource, _ value: DrawingTool
  ) -> some View {
    Button {
      tool = value
    } label: {
      HStack(spacing: 1) {
        Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
        if let badge { Image(systemName: badge).font(.system(size: 9, weight: .heavy)) }
      }
      .frame(width: 38, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tool == value ? DS.accent : Color.clear)
        )
        .foregroundStyle(tool == value ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
    .help(String(localized: label))
    .accessibilityLabel(Text(label))
  }

  private func iconButton(
    _ systemImage: String, _ label: LocalizedStringResource, tint: Color = .primary, enabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
        .frame(width: 30, height: 26)
        .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.5))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .help(String(localized: label))
    .accessibilityLabel(Text(label))
  }

  private var maskSettings: some View {
    let binding = Binding(get: { control.inputs.maskSettings }, set: { control.setMaskSettings($0) })
    return VStack(alignment: .leading, spacing: DS.controlGap) {
      CardRow(label: String(localized: "control.mask.blur")) {
        Slider(
          value: Binding(get: { binding.wrappedValue.blur }, set: { binding.wrappedValue.blur = $0 }),
          in: MaskSettings.blurRange, step: 0.5
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: binding.wrappedValue.blur.formatted(.number.precision(.fractionLength(1))))
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.blur.help"))
      CardRow(label: String(localized: "control.mask.outset")) {
        Slider(
          value: Binding(
            get: { Double(binding.wrappedValue.outset) }, set: { binding.wrappedValue.outset = Int($0.rounded()) }),
          in: Double(MaskSettings.outsetRange.lowerBound)...Double(MaskSettings.outsetRange.upperBound), step: 1
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(binding.wrappedValue.outset)")
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.outset.help"))
      Toggle(
        isOn: Binding(
          get: { binding.wrappedValue.preserveOriginal }, set: { binding.wrappedValue.preserveOriginal = $0 })
      ) {
        Text("control.mask.preserve")
      }
    }
  }

  // MARK: Draw mode: painting

  private func drawArea(for image: ReferenceImage) -> some View {
    let crop = FramingMath.cropRect(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: control.inputs.framing)
    return sized(ratio: Double(canvasWidth) / Double(max(canvasHeight, 1))) {
      GeometryReader { geometry in
        painting(image: image, crop: crop, size: geometry.size)
      }
    }
  }

  /// The picture, the drawing and the mask are layers of their own, so a stroke only changes the
  /// layer it draws on; the cursor ring moves over them.
  private func painting(image: ReferenceImage, crop: CGRect, size: CGSize) -> some View {
    // The whole image, placed so that the cut fills the view: what shows is what is sent.
    let scale = size.width / crop.width
    let frame = CGSize(width: Double(image.pixelWidth) * scale, height: Double(image.pixelHeight) * scale)
    let origin = CGPoint(x: -crop.minX * scale, y: -crop.minY * scale)
    func layer(_ picture: CGImage?) -> some View {
      Group {
        if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
      }
      .frame(width: frame.width, height: frame.height)
      .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
    }
    return ZStack(alignment: .topLeading) {
      Color.primary.opacity(0.08)
      layer(picture)
      layer(drawing.paintImage)
      layer(drawing.maskImage)
      if let hover {
        let radius = brushSize / 2 * size.width / Double(max(canvasWidth, 1))
        ZStack {
          Circle().stroke(Color.black.opacity(0.6), lineWidth: 2.5)
          Circle().stroke(Color.white, lineWidth: 1.2)
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(hover)
        .allowsHitTesting(false)
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): hover = point
      case .ended: hover = nil
      }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          hover = value.location
          drawing.stroke(
            tool: tool, to: value.location, viewSize: size, crop: crop, imageWidth: image.pixelWidth,
            canvasWidth: canvasWidth, diameter: brushSize, color: brushRGB)
        }
        .onEnded { _ in
          attempt { () throws(ControlError) in try drawing.endStroke(into: control) }
        })
  }

  private func rgb(of color: Color) -> (red: UInt8, green: UInt8, blue: UInt8) {
    let converted = NSColor(color).usingColorSpace(.sRGB) ?? .red
    func byte(_ value: CGFloat) -> UInt8 { UInt8(min(255, max(0, (value * 255).rounded()))) }
    return (byte(converted.redComponent), byte(converted.greenComponent), byte(converted.blueComponent))
  }

  private func attempt(_ action: () throws(ControlError) -> Void) {
    do { try action() } catch { report(.error(ControlText.error(error))) }
  }
}
