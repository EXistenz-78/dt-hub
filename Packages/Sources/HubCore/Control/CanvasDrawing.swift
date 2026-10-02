import CoreGraphics
import Foundation
import HubKit
import Observation

/// What the Draw mode of the canvas draws with.
public enum DrawingTool: Hashable, Sendable {
  /// Paints the mask: the area to regenerate.
  case maskAdd
  /// Takes mask away.
  case maskRemove
  /// Draws in colour on the image.
  case brush
}

/// The mask and the Brush drawing while they are being drawn (tab Control spec §3): read from the
/// store, changed by the tools a point at a time, given back to the store when the stroke ends.
/// The images for the screen (`maskImage`, `paintImage`) are updated in place, so a stroke costs a
/// few milliseconds whatever the size of the picture.
@MainActor
@Observable
public final class CanvasDrawing {
  /// The mask as a translucent orange, nil when there is no mask.
  public private(set) var maskImage: CGImage?
  /// The Brush drawing, nil when there is none.
  public private(set) var paintImage: CGImage?

  @ObservationIgnored private var mask: MaskBitmap?
  @ObservationIgnored private var paint: PaintBitmap?
  @ObservationIgnored private var maskOverlay: MaskOverlay?
  @ObservationIgnored private var paintOverlay: PaintOverlay?
  @ObservationIgnored private var loaded: Key?
  @ObservationIgnored private var smoother = StrokeSmoother()
  @ObservationIgnored private var strokeTool = DrawingTool.maskAdd
  @ObservationIgnored private var strokeRadius = 1.0
  @ObservationIgnored private var strokeColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 0)

  private struct Key: Equatable {
    let image: UUID?
    let mask: String?
    let paint: String?
  }

  /// The orange of the mask on the screen.
  private static let maskColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 140, 0)

  public init() {}

  /// Reads the mask and the drawing from the store when the image, the mask or the drawing changed
  /// under us (undo, redo, clear, a new image); what was just drawn here is already on screen.
  public func sync(with control: ControlStore) {
    let key = Key(
      image: control.inputs.image?.id, mask: control.inputs.mask?.fileName, paint: control.inputs.paint?.fileName)
    guard key != loaded else { return }
    guard let size = control.maskSize else {
      mask = nil
      paint = nil
      maskOverlay = nil
      paintOverlay = nil
      maskImage = nil
      paintImage = nil
      loaded = key
      return
    }
    let bitmap = control.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    let buffer = MaskOverlay(
      width: size.width, height: size.height, red: Self.maskColor.red, green: Self.maskColor.green,
      blue: Self.maskColor.blue, opacity: 0.55)
    if !bitmap.isEmpty { buffer?.rebuild(from: bitmap) }
    mask = bitmap
    maskOverlay = buffer
    maskImage = bitmap.isEmpty ? nil : buffer?.image()
    let layer = control.paintBitmap() ?? PaintBitmap(width: size.width, height: size.height)
    let layerBuffer = PaintOverlay(width: size.width, height: size.height)
    if !layer.isEmpty { layerBuffer?.rebuild(from: layer) }
    paint = layer
    paintOverlay = layerBuffer
    paintImage = layer.isEmpty ? nil : layerBuffer?.image()
    loaded = key
  }

  /// True while a stroke is under way.
  public var isStroking: Bool { smoother.isActive }

  /// Continues a stroke (or starts it) at a point of the view. The view shows the cut `crop` (in the
  /// start image's pixels) of the image `imageWidth` pixels wide, and fills `viewSize`; `diameter`
  /// is the tool's size in canvas pixels. A new `tool` or `color` takes effect with the next stroke.
  public func stroke(
    tool: DrawingTool, to point: CGPoint, viewSize: CGSize, crop: CGRect, imageWidth: Int, canvasWidth: Int,
    diameter: Double, color: (red: UInt8, green: UInt8, blue: UInt8)
  ) {
    guard let reference = mask, imageWidth > 0, viewSize.width > 0, viewSize.height > 0 else { return }
    if !smoother.isActive {
      strokeTool = tool
      strokeColor = color
      strokeRadius = reference.brushRadius(diameter: diameter, canvasWidth: canvasWidth, crop: crop, imageWidth: imageWidth)
    }
    let target = reference.point(forViewPoint: point, viewSize: viewSize, crop: crop, imageWidth: imageWidth)
    draw(smoother.add(target, spacing: max(strokeRadius / 2, 1)))
  }

  /// Ends the stroke and gives what was drawn to the store (one step of its history).
  public func endStroke(into control: ControlStore) throws(ControlError) {
    guard smoother.isActive else { return }
    draw(smoother.finish())
    switch strokeTool {
    case .maskAdd, .maskRemove:
      if let mask { try control.commitMask(mask) }
    case .brush:
      if let paint { try control.commitPaint(paint) }
    }
    loaded = Key(
      image: control.inputs.image?.id, mask: control.inputs.mask?.fileName, paint: control.inputs.paint?.fileName)
  }

  /// Strokes along the points, then refreshes the picture of the layer that changed.
  private func draw(_ points: [CGPoint]) {
    guard let first = points.first else { return }
    var dirty = CGRect.null
    // A single point is a dot: stroked from itself to itself.
    let rest = points.count > 1 ? Array(points.dropFirst()) : [first]
    switch strokeTool {
    case .maskAdd, .maskRemove:
      guard var bitmap = mask else { return }
      mask = nil  // the one reference, so the buffer is changed in place
      var from = first
      for to in rest {
        dirty = dirty.union(bitmap.stroke(from: from, to: to, radius: strokeRadius, erase: strokeTool == .maskRemove))
        from = to
      }
      mask = bitmap
      maskOverlay?.update(from: bitmap, rect: dirty)
      maskImage = maskOverlay?.image()
    case .brush:
      guard var layer = paint else { return }
      paint = nil
      var from = first
      for to in rest {
        dirty = dirty.union(
          layer.stroke(
            from: from, to: to, radius: strokeRadius, red: strokeColor.red, green: strokeColor.green,
            blue: strokeColor.blue))
        from = to
      }
      paint = layer
      paintOverlay?.update(from: layer, rect: dirty)
      paintImage = paintOverlay?.image()
    }
  }
}
