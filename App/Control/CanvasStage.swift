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
  /// Opens the card in its own window; nil in that window itself, which has no such button.
  var detach: (() -> Void)?
  /// True in the card's own window: the card is always open there.
  var isInOwnWindow = false

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
      isExpanded: isInOwnWindow ? .constant(true) : generation.cards.binding("control.stage")
    ) {
      if let detach {
        Button(action: detach) {
          Image(systemName: "arrow.up.forward.square").font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(String(localized: "control.stage.detach.help"))
        .accessibilityLabel(String(localized: "control.stage.detach.help"))
      }
    } content: {
      VStack(spacing: DS.rowGap) {
        if let image = control.inputs.image {
          modePicker
          if mode == .draw { tools }
          if mode == .canvas {
            stage(for: image)
            zoomRow(for: image)
            if control.hasMargins(canvasWidth: canvasWidth, canvasHeight: canvasHeight) { fillRow }
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

  /// The board around the canvas in Canvas mode, as a share of the canvas on each side: what the image
  /// puts outside the canvas shows there, darkened.
  private static let boardMargin = 0.12

  private func stage(for image: ReferenceImage) -> some View {
    sized(ratio: Double(canvasWidth) / Double(max(canvasHeight, 1))) {
      stageContent(for: image)
    }
  }

  private func stageContent(for image: ReferenceImage) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      let crop = FramingMath.cropRect(
        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
        canvasHeight: canvasHeight, framing: control.inputs.framing)
      let inset = Self.boardMargin / (1 + 2 * Self.boardMargin)
      let canvas = CGRect(
        x: size.width * inset, y: size.height * inset, width: size.width * (1 - 2 * inset),
        height: size.height * (1 - 2 * inset))
      let scale = canvas.width / crop.width
      let frame = CGSize(width: Double(image.pixelWidth) * scale, height: Double(image.pixelHeight) * scale)
      let origin = CGPoint(x: canvas.minX - crop.minX * scale, y: canvas.minY - crop.minY * scale)
      ZStack(alignment: .topLeading) {
        Color.primary.opacity(0.08)
        checkerboard(in: canvas)
        if picture != nil {
          imageLayer(picture, origin: origin, size: frame)
        } else {
          Color.primary.opacity(0.08).frame(width: frame.width, height: frame.height).position(
            x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
        }
        imageLayer(drawing.paintImage, origin: origin, size: frame)
        imageLayer(drawing.maskImage, origin: origin, size: frame)
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          path.addRect(canvas)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: canvas.width, height: canvas.height)
          .position(x: canvas.midX, y: canvas.midY)
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let start = dragStart ?? control.inputs.framing
            dragStart = start
            move(from: start, by: value.translation, scale: scale, image: image, crop: crop)
          }
          .onEnded { _ in dragStart = nil })
    }
  }

  /// A layer of the image's own size and place in the view.
  private func imageLayer(_ picture: CGImage?, origin: CGPoint, size: CGSize) -> some View {
    Group {
      if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
    }
    .frame(width: size.width, height: size.height)
    .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
  }

  /// Squares under the canvas: what the image does not cover shows through them.
  private func checkerboard(in rect: CGRect) -> some View {
    Canvas { context, _ in
      let cell = 10.0
      context.fill(Path(rect), with: .color(Color(white: 0.86)))
      var dark = Path()
      var row = 0
      var y = rect.minY
      while y < rect.maxY {
        var column = 0
        var x = rect.minX
        while x < rect.maxX {
          if (row + column) % 2 == 0 {
            dark.addRect(CGRect(x: x, y: y, width: min(cell, rect.maxX - x), height: min(cell, rect.maxY - y)))
          }
          x += cell
          column += 1
        }
        y += cell
        row += 1
      }
      context.fill(dark, with: .color(Color(white: 0.7)))
    }
    .allowsHitTesting(false)
  }

  /// The image follows the pointer on the axes where it and the canvas do not coincide.
  private func move(from start: Framing, by translation: CGSize, scale: Double, image: ReferenceImage, crop: CGRect) {
    let slackX = Double(image.pixelWidth) - crop.width
    let slackY = Double(image.pixelHeight) - crop.height
    var x = start.offsetX
    var y = start.offsetY
    if abs(slackX) > 0.5 { x -= 2 * translation.width / scale / slackX }
    if abs(slackY) > 0.5 { y -= 2 * translation.height / scale / slackY }
    control.setOffset(x: x, y: y)
  }

  /// The zoom: −100 shrinks the image (margins to regenerate), +100 enlarges it. It stops, with a tick,
  /// at 0 (fill) and where the whole image just fits.
  private func zoomRow(for image: ReferenceImage) -> some View {
    let contain = FramingMath.zoomContain(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
    let zoom = control.inputs.framing.zoom
    return CardRow(label: String(localized: "control.stage.zoom")) {
      Slider(
        value: Binding(get: { zoom }, set: { setZoom($0, contain: contain) }), in: Framing.zoomRange
      )
      .frame(minWidth: 120)
    } control: {
      HStack(spacing: 2) {
        Text(verbatim: Int(zoom.rounded()).formatted(.number.sign(strategy: .always(includingZero: false))))
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        iconButton("arrow.counterclockwise", "control.stage.zoom.reset", enabled: control.inputs.framing != Framing()) {
          control.resetFraming()
        }
      }
    }
  }

  /// What fills the margins: automatic follows the LoRAs (an outpaint LoRA asks for a flat grey or green
  /// and no mask), or the user picks. Shown only when the image leaves margins.
  private var fillRow: some View {
    let automatic = MarginFill.automatic(loras: generation.parameters.loras)
    return CardRow(label: String(localized: "control.stage.fill")) {
      EmptyView()
    } control: {
      Picker(
        String(localized: "control.stage.fill"),
        selection: Binding(get: { control.inputs.marginFill }, set: { control.setMarginFill($0) })
      ) {
        Text(String(format: String(localized: "control.fill.automatic"), fillName(automatic))).tag(MarginFill?.none)
        ForEach(MarginFill.allCases, id: \.self) { fill in
          Text(fillName(fill)).tag(MarginFill?.some(fill))
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .help(String(localized: "control.fill.help"))
    }
  }

  private func fillName(_ fill: MarginFill) -> String {
    switch fill {
    case .edges: String(localized: "control.fill.edges")
    case .gray: String(localized: "control.fill.gray")
    case .green: String(localized: "control.fill.green")
    }
  }

  private func setZoom(_ raw: Double, contain: Double) {
    var value = raw
    for target in [0.0, contain] where abs(raw - target) < 3 { value = target }
    if value != raw, value != control.inputs.framing.zoom {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    control.setZoom(value)
  }

  @ViewBuilder private func caption(for image: ReferenceImage) -> some View {
    let framing = control.inputs.framing
    let margins = FramingMath.margins(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: framing)
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, zoom: min(0, framing.zoom))
    let crop = FramingMath.cropRect(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: framing)
    let canMove =
      abs(Double(image.pixelWidth) - crop.width) > 0.5 || abs(Double(image.pixelHeight) - crop.height) > 0.5
    VStack(alignment: .leading, spacing: 2) {
      Text(
        String(
          format: String(localized: "control.stage.size"), canvasWidth, canvasHeight)
      )
      .font(.caption).foregroundStyle(.secondary)
      if !margins.isEmpty {
        Text(String(format: String(localized: "control.stage.margins"), marginList(margins)))
          .font(.caption).foregroundStyle(.secondary)
      }
      if framing.zoom > 0 {
        let share = FramingMath.usedShare(
          imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
          canvasHeight: canvasHeight, framing: framing)
        Text(String(format: String(localized: "control.stage.used"), Int((share * 100).rounded())))
          .font(.caption).foregroundStyle(.secondary)
      } else if let axis = loss.axis {
        Text(
          String(
            format: String(localized: axis == .vertical ? "control.stage.loss.vertical" : "control.stage.loss.horizontal"),
            Int((loss.fraction * 100).rounded()))
        )
        .font(.caption).foregroundStyle(loss.fraction > 1.0 / 3.0 ? DS.remove : .secondary)
      }
      if canMove { Text("control.stage.drag").font(.caption).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "left 12%, right 12%": the sides that have a margin, as a share of the canvas.
  private func marginList(_ margins: FramingMath.Margins) -> String {
    var parts: [String] = []
    func add(_ key: String.LocalizationValue, _ pixels: Double, of side: Int) {
      if pixels >= 0.5 {
        parts.append(String(format: String(localized: key), Int((pixels / Double(max(side, 1)) * 100).rounded())))
      }
    }
    add("control.stage.margin.top", margins.top, of: canvasHeight)
    add("control.stage.margin.bottom", margins.bottom, of: canvasHeight)
    add("control.stage.margin.left", margins.left, of: canvasWidth)
    add("control.stage.margin.right", margins.right, of: canvasWidth)
    return parts.joined(separator: ", ")
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
    let fill = generation.marginFill
    return ZStack(alignment: .topLeading) {
      if fill == .green { Color(red: 0, green: 1, blue: 0) } else { Color(white: 0.5) }
      layer(picture)
      layer(drawing.paintImage)
      layer(drawing.maskImage)
      // What the image leaves uncovered is regenerated when it goes in the mask: it shows like the mask.
      // With a flat grey or green fill (an outpaint LoRA) it shows as that colour, and nothing is masked.
      if fill.sendsMask {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          path.addRect(CGRect(origin: origin, size: frame))
        }
        .fill(Color(red: 1, green: 140 / 255, blue: 0).opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
      }
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
