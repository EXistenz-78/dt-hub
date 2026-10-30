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
  /// The view zoom of the Draw mode (wheel and pinch; Space + drag moves it). Never below the fit.
  @State private var drawZoom = ResultZoom()
  @State private var spaceDown = false
  @State private var panLast: CGSize = .zero
  @State private var pinchLast: CGFloat = 1
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
    Group {
      if isInOwnWindow { windowContent } else { card }
    }
    .task(id: control.inputs.image?.id) {
      guard let request = control.previewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
    .task(id: key) { drawing.sync(with: control) }
    .onChange(of: brushColor) { brushRGB = rgb(of: brushColor) }
    .onChange(of: mode) { drawZoom.reset() }
    .onChange(of: control.inputs.image?.id) { drawZoom.reset() }
  }

  /// The card in the Control tab.
  private var card: some View {
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
            rotationRow
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
  }

  /// The card's own window: no card, no title, no mode choice, only the drawing. The tools on top, the
  /// settings of the mask at the bottom, and the picture as large as what is left allows (the window may
  /// be moved to an iPad with Sidecar and drawn on with the Pencil).
  private var windowContent: some View {
    VStack(spacing: DS.controlGap) {
      if let image = control.inputs.image {
        tools
        GeometryReader { proxy in
          let ratio = Double(canvasWidth) / Double(max(canvasHeight, 1))
          let width = min(proxy.size.width, proxy.size.height * ratio)
          painting(image: image, crop: cropRect(of: image), size: CGSize(width: width, height: width / ratio))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if tool != .brush || control.inputs.mask != nil { maskSettings }
      } else {
        empty
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func cropRect(of image: ReferenceImage) -> CGRect {
    FramingMath.cropRect(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: control.inputs.framing)
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
          Color.primary.opacity(0.08).frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(control.inputs.framing.rotation))
            .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
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
          .onEnded { _ in dragStart = nil }
      )
      .gesture(
        MagnifyGesture()
          .onChanged { value in
            zoomCanvas(by: value.magnification / pinchLast, at: value.startLocation, canvas: canvas, image: image)
            pinchLast = value.magnification
          }
          .onEnded { _ in pinchLast = 1 }
      )
      .background(
        CanvasWheelMonitor(isActive: true) { point, factor in
          // The monitor reports from the centre of the view, y down.
          let location = CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
          zoomCanvas(by: factor, at: location, canvas: canvas, image: image)
        }
      )
    }
  }

  /// The wheel and the pinch move the zoom of the slider (same range) keeping still the point under the cursor.
  private func zoomCanvas(by factor: Double, at location: CGPoint, canvas: CGRect, image: ReferenceImage) {
    guard canvas.width > 0, canvas.height > 0 else { return }
    let fraction = CGPoint(x: (location.x - canvas.minX) / canvas.width, y: (location.y - canvas.minY) / canvas.height)
    let next = FramingMath.zoomed(
      control.inputs.framing, by: factor, atCanvasFraction: fraction, imageWidth: image.pixelWidth,
      imageHeight: image.pixelHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    control.setZoom(next.zoom, offsetX: next.offsetX, offsetY: next.offsetY)
  }

  /// A layer of the image's own size and place in the view.
  private func imageLayer(_ picture: CGImage?, origin: CGPoint, size: CGSize) -> some View {
    Group {
      if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
    }
    .frame(width: size.width, height: size.height)
    .rotationEffect(.degrees(control.inputs.framing.rotation))
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
        iconButton(
          "arrow.counterclockwise", "control.stage.zoom.reset",
          enabled: control.inputs.framing.zoom != 0 || control.inputs.framing.offsetX != 0
            || control.inputs.framing.offsetY != 0
        ) {
          control.setZoom(0, offsetX: 0, offsetY: 0)
        }
      }
    }
  }

  /// The turn of the image in the canvas, about its centre: −180° to +180°, clockwise, with a tick at 0.
  private var rotationRow: some View {
    let rotation = control.inputs.framing.rotation
    return CardRow(label: String(localized: "control.stage.rotation")) {
      Slider(
        value: Binding(get: { rotation }, set: { setRotation($0) }), in: Framing.rotationRange
      )
      .frame(minWidth: 120)
    } control: {
      HStack(spacing: 2) {
        Text(verbatim: "\(Int(rotation.rounded()).formatted(.number.sign(strategy: .always(includingZero: false))))°")
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        iconButton("arrow.counterclockwise", "control.stage.rotation.reset", enabled: rotation != 0) {
          control.setRotation(0)
        }
      }
    }
  }

  private func setRotation(_ raw: Double) {
    var value = raw.rounded()
    if abs(value) < 3 { value = 0 }
    if value == 0, control.inputs.framing.rotation != 0 {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    control.setRotation(value)
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
        Text(String(format: String(localized: "control.stage.margins"), marginList(margins, corners: margins.cornersUncovered)))
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
  private func marginList(_ margins: FramingMath.Margins, corners: Bool = false) -> String {
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
    if parts.isEmpty, corners { parts.append(String(localized: "control.stage.margin.corners")) }
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
    let crop = cropRect(of: image)
    return sized(ratio: Double(canvasWidth) / Double(max(canvasHeight, 1))) {
      GeometryReader { geometry in
        painting(image: image, crop: crop, size: geometry.size)
      }
    }
  }

  /// The picture, the drawing and the mask are layers of their own, so a stroke only changes the
  /// layer it draws on; the cursor ring moves over them. The wheel and the pinch zoom the view (never
  /// below the fit); with Space held a drag moves it instead of drawing.
  private func painting(image: ReferenceImage, crop: CGRect, size: CGSize) -> some View {
    // The whole image, placed so that the cut fills the view: what shows is what is sent.
    let scale = size.width / crop.width
    let frame = CGSize(width: Double(image.pixelWidth) * scale, height: Double(image.pixelHeight) * scale)
    let origin = CGPoint(x: -crop.minX * scale, y: -crop.minY * scale)
    let rotation = control.inputs.framing.rotation
    func layer(_ picture: CGImage?) -> some View {
      Group {
        if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
      }
      .frame(width: frame.width, height: frame.height)
      .rotationEffect(.degrees(rotation))
      .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
    }
    let fill = generation.marginFill
    let view = CGPoint(x: size.width / 2, y: size.height / 2)
    // From a point of the view (as the gesture gives it) to the same point on the unzoomed picture.
    func unzoomed(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: (point.x - view.x - drawZoom.offset.x) / drawZoom.scale + view.x,
        y: (point.y - view.y - drawZoom.offset.y) / drawZoom.scale + view.y)
    }
    let content = ZStack(alignment: .topLeading) {
      if fill == .green { Color(red: 0, green: 1, blue: 0) } else { Color(white: 0.5) }
      layer(picture)
      layer(drawing.paintImage)
      layer(drawing.maskImage)
      // What the image leaves uncovered is regenerated when it goes in the mask: it shows like the mask.
      // With a flat grey or green fill (an outpaint LoRA) it shows as that colour, and nothing is masked.
      if fill.sendsMask {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          let rect = CGRect(origin: origin, size: frame)
          let turn = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: rotation * .pi / 180).translatedBy(x: -rect.midX, y: -rect.midY)
          path.addPath(Path(rect).applying(turn))
        }
        .fill(Color(red: 1, green: 140 / 255, blue: 0).opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
      }
    }
    .frame(width: size.width, height: size.height)
    .scaleEffect(drawZoom.scale)
    .offset(x: drawZoom.offset.x, y: drawZoom.offset.y)
    return ZStack(alignment: .topLeading) {
      content
      if let hover {
        let radius = brushSize / 2 * size.width / Double(max(canvasWidth, 1)) * drawZoom.scale
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
          if spaceDown {
            let step = CGSize(
              width: value.translation.width - panLast.width, height: value.translation.height - panLast.height)
            panLast = value.translation
            drawZoom.pan(by: step, view: size, fitted: size)
            return
          }
          drawing.stroke(
            tool: tool, to: unzoomed(value.location), viewSize: size, crop: crop, imageWidth: image.pixelWidth,
            canvasWidth: canvasWidth, diameter: brushSize, color: brushRGB, rotation: rotation)
        }
        .onEnded { _ in
          if spaceDown || panLast != .zero { panLast = .zero; return }
          attempt { () throws(ControlError) in try drawing.endStroke(into: control) }
        })
    .gesture(
      MagnifyGesture()
        .onChanged { value in
          let anchor = CGPoint(x: value.startLocation.x - view.x, y: value.startLocation.y - view.y)
          drawZoom.zoom(by: value.magnification / pinchLast, at: anchor, view: size, fitted: size)
          pinchLast = value.magnification
        }
        .onEnded { _ in pinchLast = 1 }
    )
    .background(
      CanvasWheelMonitor(isActive: true) { point, factor in
        drawZoom.zoom(by: factor, at: point, view: size, fitted: size)
      }
    )
    .background(SpaceKeyMonitor(isDown: $spaceDown))
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

/// The scroll wheel over this view: calls `onZoom(anchor, factor)` with the point under the cursor, from the centre of
/// the view with y down, and takes the event.
private struct CanvasWheelMonitor: NSViewRepresentable {
  var isActive: Bool
  var onZoom: (CGPoint, CGFloat) -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isActive = isActive
    context.coordinator.onZoom = onZoom
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var isActive = false
    var onZoom: (CGPoint, CGFloat) -> Void = { _, _ in }
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, self.isActive, let view = self.view, let window = view.window,
            unsafeEvent.window === window
          else { return false }
          let local = view.convert(unsafeEvent.locationInWindow, from: nil)
          guard view.bounds.contains(local), unsafeEvent.scrollingDeltaY != 0 else { return false }
          // A wheel notch is a coarse step; a trackpad sends many small ones.
          let rate: CGFloat = unsafeEvent.hasPreciseScrollingDeltas ? 0.01 : 0.08
          let anchor = CGPoint(x: local.x - view.bounds.midX, y: view.bounds.midY - local.y)
          self.onZoom(anchor, exp(unsafeEvent.scrollingDeltaY * rate))
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// Whether Space is held while this window is the key one (it moves the zoomed drawing instead of drawing).
private struct SpaceKeyMonitor: NSViewRepresentable {
  @Binding var isDown: Bool

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.binding = $isDown
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.binding = $isDown }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var binding: Binding<Bool>?
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, unsafeEvent.keyCode == 49, let window = self.view?.window, unsafeEvent.window === window,
            window.isKeyWindow, !(window.firstResponder is NSText)
          else { return false }
          self.binding?.wrappedValue = unsafeEvent.type == .keyDown
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      binding?.wrappedValue = false
    }
  }
}
