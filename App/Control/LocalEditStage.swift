import CoreGraphics
import HubCore
import HubKit
import SwiftUI

/// The Local Editing mode of the Canvas card (spec: Editing locale). Without a session it shows the whole start
/// image and a rectangle drawn on it (drag to draw, drag inside to move, drag a corner to resize, Esc to remove),
/// always as the crop it will become, and «Use the Crop». During a session it shows the whole image with the
/// retouch shown put back in place, with ‹ n/m › to go through the attempts, Match Colours, Cancel and Confirm.
struct LocalEditStage: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  /// Reports what went wrong.
  let report: (ControlMessage) -> Void

  /// What a drag on the stage does, decided where it starts.
  private enum DragKind {
    case draw(from: CGPoint)
    case move(from: CGRect)
    case resize(anchor: CGPoint)
  }

  /// The whole image, longest side 1400.
  @State private var picture: CGImage?
  /// The whole image with the shown attempt put back, at the size of `picture`.
  @State private var montage: CGImage?
  /// The rectangle drawn, in pixels of the image (not kept before «Use the Crop»).
  @State private var drawn: CGRect?
  @State private var drag: DragKind?
  /// The attempt shown: 0 is the newest.
  @State private var shownIndex = 0
  @State private var isConfirming = false
  /// True while «Use the Crop» cuts the pictures.
  @State private var isBeginning = false

  @Environment(\.controlViewportHeight) private var viewportHeight

  private var control: ControlStore { generation.control }
  /// The image the rectangle is drawn on: the original of the session, or the start image.
  private var original: ReferenceImage? { control.inputs.localEdit?.original ?? control.inputs.image }

  /// Size of a corner's handle, in points.
  private static let handle = 10.0
  /// What the card holds besides the stage: the stage is as tall as the window minus this.
  private static let chromeHeight = 300.0

  var body: some View {
    let attempts = generation.localEditAttempts
    VStack(spacing: DS.rowGap) {
      if let original {
        stage(for: original, attempts: attempts)
        if let session = control.inputs.localEdit {
          sessionControls(session, attempts: attempts)
        } else {
          drawControls(for: original)
        }
      }
    }
    .task(id: original?.fileName) {
      guard let request = control.originalPreviewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
    .task(id: MontageKey(attempt: shownAttempt(in: attempts)?.id, session: control.inputs.localEdit, ready: picture != nil)) {
      await makeMontage(attempts: attempts)
    }
    .onChange(of: attempts.count) { old, new in
      if new > old { shownIndex = 0 }
    }
    .onChange(of: control.inputs.localEdit?.id) { drawn = nil }
    .background { escapeShortcut }
  }

  // MARK: The stage

  private func stage(for image: ReferenceImage, attempts: [GeneratedImage]) -> some View {
    let ratio = Double(image.pixelWidth) / Double(max(image.pixelHeight, 1))
    let tallest = max(340, viewportHeight - Self.chromeHeight)
    return Color.clear
      .aspectRatio(ratio, contentMode: .fit)
      .frame(maxWidth: tallest * ratio)
      .overlay {
        GeometryReader { geometry in
          let view = LocalEditViewMath(
            imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, viewSize: geometry.size)
          stageContent(view: view, attempts: attempts)
        }
      }
      .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func stageContent(view: LocalEditViewMath, attempts: [GeneratedImage]) -> some View {
    let frame = view.imageFrame
    let session = control.inputs.localEdit
    let shown = session != nil && !attempts.isEmpty ? (montage ?? picture) : picture
    let rect = session?.rect ?? snapped(for: view)
    ZStack(alignment: .topLeading) {
      Group {
        if let shown {
          Image(decorative: shown, scale: 1).resizable().interpolation(.high)
        } else {
          Color.primary.opacity(0.08)
        }
      }
      .frame(width: frame.width, height: frame.height)
      .position(x: frame.midX, y: frame.midY)
      if let rect {
        let box = view.viewRect(of: rect)
        if session == nil {
          // Outside the crop is darkened, the crop has a handle on each corner.
          Path { path in
            path.addRect(frame)
            path.addRect(box)
          }
          .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
          Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
          ForEach(Array(corners(of: box).enumerated()), id: \.offset) { _, corner in
            Rectangle().fill(DS.accent).frame(width: Self.handle, height: Self.handle)
              .position(corner)
          }
        } else if attempts.isEmpty {
          Rectangle()
            .strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    .contentShape(Rectangle())
    .gesture(drawGesture(view: view), isEnabled: session == nil)
  }

  private func corners(of box: CGRect) -> [CGPoint] {
    [
      CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
      CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
    ]
  }

  /// The crop the drawn rectangle becomes.
  private func snapped(for view: LocalEditViewMath) -> PixelRect? {
    guard let drawn else { return nil }
    return LocalEditMath.snapped(drawn, imageWidth: view.imageWidth, imageHeight: view.imageHeight)
  }

  private func drawGesture(view: LocalEditViewMath) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        let kind = drag ?? startDrag(at: value.startLocation, view: view)
        drag = kind
        switch kind {
        case .draw(let from):
          drawn = rectangle(from: from, to: view.pixel(at: value.location))
        case .resize(let anchor):
          drawn = rectangle(from: anchor, to: view.pixel(at: value.location))
        case .move(let from):
          let start = view.pixel(at: value.startLocation)
          let now = view.pixel(at: value.location)
          let dx = min(max(now.x - start.x, -from.minX), CGFloat(view.imageWidth) - from.maxX)
          let dy = min(max(now.y - start.y, -from.minY), CGFloat(view.imageHeight) - from.maxY)
          drawn = from.offsetBy(dx: dx, dy: dy)
        }
      }
      .onEnded { _ in
        drag = nil
        // What stays is the crop shown: moving or resizing it again starts from there.
        drawn = snapped(for: view)?.cgRect
      }
  }

  /// A corner's handle resizes from the opposite corner, the inside moves, elsewhere draws a new rectangle.
  private func startDrag(at location: CGPoint, view: LocalEditViewMath) -> DragKind {
    if let rect = snapped(for: view) {
      let box = view.viewRect(of: rect)
      let pixels = rect.cgRect
      let opposite = [
        CGPoint(x: pixels.maxX, y: pixels.maxY), CGPoint(x: pixels.minX, y: pixels.maxY),
        CGPoint(x: pixels.maxX, y: pixels.minY), CGPoint(x: pixels.minX, y: pixels.minY),
      ]
      for (corner, anchor) in zip(corners(of: box), opposite)
      where abs(location.x - corner.x) <= Self.handle && abs(location.y - corner.y) <= Self.handle {
        return .resize(anchor: anchor)
      }
      if box.contains(location) { return .move(from: pixels) }
    }
    return .draw(from: view.pixel(at: location))
  }

  private func rectangle(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  /// Esc removes the drawn rectangle.
  @ViewBuilder
  private var escapeShortcut: some View {
    if drawn != nil, control.inputs.localEdit == nil {
      Button {
        drawn = nil
      } label: {
        EmptyView()
      }
      .keyboardShortcut(.escape, modifiers: [])
      .opacity(0)
      .allowsHitTesting(false)
    }
  }

  // MARK: Without a session

  private func drawControls(for image: ReferenceImage) -> some View {
    let tooSmall = image.pixelWidth < LocalEditMath.minSide || image.pixelHeight < LocalEditMath.minSide
    let crop = drawn.flatMap {
      LocalEditMath.snapped($0, imageWidth: image.pixelWidth, imageHeight: image.pixelHeight)
    }
    return HStack(spacing: DS.controlGap) {
      Group {
        if tooSmall {
          Text("localEdit.tooSmall")
        } else if let crop {
          Text(
            verbatim: String(
              format: String(localized: "localEdit.size"), crop.width, crop.height, crop.x, crop.y))
          .monospacedDigit()
        } else {
          Text("localEdit.drawHint")
        }
      }
      .font(.callout).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      if isBeginning { ProgressView().controlSize(.small) }
      Button("localEdit.useCrop") {
        guard let crop else { return }
        isBeginning = true
        Task {
          defer { isBeginning = false }
          do throws(ControlError) {
            try await generation.beginLocalEdit(rect: crop)
            drawn = nil
          } catch {
            report(.error(ControlText.error(error)))
          }
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .disabled(crop == nil || isBeginning)
      .help(tooSmall ? String(localized: "localEdit.tooSmall") : "")
    }
  }

  // MARK: During a session

  private func shownAttempt(in attempts: [GeneratedImage]) -> GeneratedImage? {
    attempts.isEmpty ? nil : attempts[min(shownIndex, attempts.count - 1)]
  }

  private func sessionControls(_ session: LocalEditSession, attempts: [GeneratedImage]) -> some View {
    let index = min(shownIndex, max(attempts.count - 1, 0))
    return VStack(alignment: .leading, spacing: DS.rowGap) {
      HStack(spacing: DS.controlGap) {
        if attempts.isEmpty {
          Text("localEdit.noAttempt").font(.callout).foregroundStyle(.secondary)
        } else {
          // The newest is 1: ‹ goes towards it, › towards older ones.
          Button {
            shownIndex = index - 1
          } label: {
            Image(systemName: "chevron.left")
          }
          .buttonStyle(.plain)
          .disabled(isConfirming || index == 0)
          Text(verbatim: String(format: String(localized: "localEdit.attempt"), index + 1, attempts.count))
            .font(.callout).monospacedDigit()
          Button {
            shownIndex = index + 1
          } label: {
            Image(systemName: "chevron.right")
          }
          .buttonStyle(.plain)
          .disabled(isConfirming || index >= attempts.count - 1)
        }
        Spacer()
        Toggle(
          String(localized: "localEdit.matchColors"),
          isOn: Binding(get: { session.matchColors }, set: { control.setLocalEditMatchColors($0) })
        )
        .toggleStyle(DSCheckboxToggleStyle())
        .disabled(isConfirming)
      }
      HStack(spacing: DS.controlGap) {
        Spacer()
        Button("localEdit.cancel") { control.cancelLocalEdit() }
          .buttonStyle(DSPillButtonStyle())
          .disabled(isConfirming)
        if isConfirming { ProgressView().controlSize(.small) }
        Button("localEdit.confirm") { confirm(shownAttempt(in: attempts)) }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(isConfirming || attempts.isEmpty)
          .help(attempts.isEmpty ? String(localized: "localEdit.noAttempt") : "")
      }
    }
  }

  private func confirm(_ attempt: GeneratedImage?) {
    guard let attempt else { return }
    isConfirming = true
    Task {
      defer { isConfirming = false }
      do throws(ControlError) {
        try await generation.confirmLocalEdit(attempt: attempt)
      } catch {
        report(.error(ControlText.error(error)))
      }
    }
  }

  /// What the montage of the preview depends on.
  private struct MontageKey: Equatable {
    let attempt: UUID?
    let session: LocalEditSession?
    let ready: Bool
  }

  /// The shown attempt put back into the reduced original, as the confirm will do at full size: the crop and
  /// the attempt are reduced by the same factor as the original. Made away from the main actor.
  private func makeMontage(attempts: [GeneratedImage]) async {
    guard let session = control.inputs.localEdit, let picture, let attempt = shownAttempt(in: attempts) else {
      montage = nil
      return
    }
    let rect = LocalEditViewMath.scaled(
      session.rect, fromWidth: session.original.pixelWidth, fromHeight: session.original.pixelHeight,
      toWidth: picture.width, toHeight: picture.height)
    let retouch = attempt.image
    let matchColors = session.matchColors
    let made = await Task.detached(priority: .userInitiated) { () -> CGImage? in
      guard rect.width > 0, rect.height > 0, let scaled = Self.resized(retouch, width: rect.width, height: rect.height)
      else { return nil }
      return LocalEditCompositor.montage(original: picture, retouch: scaled, rect: rect, matchColors: matchColors)
    }.value
    guard !Task.isCancelled else { return }
    montage = made
  }

  /// A picture drawn at exactly `width × height`.
  nonisolated private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
