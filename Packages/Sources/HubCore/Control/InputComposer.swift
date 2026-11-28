import CoreGraphics
import Foundation
import HubKit

/// Prepares the Control tab's images for a RUN (tab Control spec §6).
public enum InputComposer {
  /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
  /// be made (a size of zero).
  /// With `paint` (the Brush drawing, in the image's own coordinates) it is put over the image in
  /// the same cut. The margins the image leaves are `fill`: its own edge pixels stretched outwards, or a
  /// flat grey or green. `resampling` scales the image (Core Graphics is what DT Hub always did); with another algorithm
  /// the image is scaled first, then placed at the nearest whole pixel and drawn without further interpolation.
  public static func frame(
    _ image: CGImage, toWidth width: Int, height: Int, framing: Framing, paint: PaintBitmap? = nil,
    fill: MarginFill = .edges, resampling: Resampling = .coreGraphics
  ) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let crop = FramingMath.cropRect(
      imageWidth: image.width, imageHeight: image.height, canvasWidth: width, canvasHeight: height, framing: framing)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    // The image drawn so that the cut fills the canvas (Core Graphics counts from the bottom-left).
    let scale = Double(width) / crop.width
    var drawn = CGRect(
      x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
      width: Double(image.width) * scale, height: Double(image.height) * scale)
    let rotation = framing.clamped().rotation
    var image = image
    // Where the image goes: the whole drawn rect, or with another algorithm the part of it the canvas shows.
    var placed = drawn
    if resampling != .coreGraphics {
      let scaledWidth = max(1, Int(drawn.width.rounded()))
      let scaledHeight = max(1, Int(drawn.height.rounded()))
      drawn = CGRect(
        x: drawn.minX.rounded(), y: drawn.minY.rounded(), width: Double(scaledWidth), height: Double(scaledHeight))
      if scaledWidth == image.width, scaledHeight == image.height {
        // 1:1: not resampled at all (Mitchell and B-spline would soften it even at scale 1).
        placed = drawn
      } else {
        // Only the part the canvas shows is made: at a high zoom the whole picture would take hundreds of megabytes.
        let region = visibleRegion(drawn: drawn, canvasWidth: width, canvasHeight: height, rotation: rotation)
        guard
          let scaled = ImageResampler.scaled(
            image, toWidth: scaledWidth, height: scaledHeight, with: resampling, region: region)
        else { return nil }
        image = scaled
        placed = CGRect(
          x: drawn.minX + region.minX, y: drawn.minY + region.minY, width: Double(scaled.width),
          height: Double(scaled.height))
      }
      // Already at scale: unturned, it is copied pixel for pixel; a turn still has to be interpolated.
      context.interpolationQuality = rotation == 0 ? .none : .high
    }
    switch fill {
    case .edges where rotation != 0:
      extendRotatedEdges(
        of: image, placed: placed, pivot: drawn, rotation: rotation, in: context, width: width, height: height)
    case .edges:
      extendEdges(of: image, drawn: placed, in: context, width: width, height: height)
    case .gray, .green:
      context.setFillColorSpace(CGColorSpaceCreateDeviceRGB())
      context.setFillColor(fill == .gray ? [0.5, 0.5, 0.5, 1] : [0, 1, 0, 1])
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    context.saveGState()
    turn(context, about: drawn, rotation: rotation)
    context.draw(image, in: placed)
    context.interpolationQuality = .high
    if let layer = paint?.cgImage() { context.draw(layer, in: drawn) }
    context.restoreGState()
    return context.makeImage()
  }

  /// The part of the scaled image the canvas shows, in the scaled image's pixels counted from its bottom-left (as Core
  /// Image and Core Graphics count).
  /// The canvas's corners are turned back about the drawn rect's centre (the image is turned about it), so with a turn
  /// the region is the box around what the canvas sees. Whole pixels; the whole picture when the canvas sees none of it.
  static func visibleRegion(drawn: CGRect, canvasWidth: Int, canvasHeight: Int, rotation: Double) -> CGRect {
    let angle = rotation * .pi / 180  // `turn` rotates by −angle: undo it
    let centre = CGPoint(x: drawn.midX, y: drawn.midY)
    let corners = [
      CGPoint(x: 0, y: 0), CGPoint(x: canvasWidth, y: 0), CGPoint(x: 0, y: canvasHeight),
      CGPoint(x: canvasWidth, y: canvasHeight),
    ].map { point -> CGPoint in
      let dx = point.x - centre.x
      let dy = point.y - centre.y
      return CGPoint(
        x: centre.x + dx * cos(angle) - dy * sin(angle) - drawn.minX,
        y: centre.y + dx * sin(angle) + dy * cos(angle) - drawn.minY)
    }
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let box = CGRect(
      x: xs.min()!.rounded(.down), y: ys.min()!.rounded(.down), width: (xs.max()!.rounded(.up) - xs.min()!.rounded(.down)),
      height: (ys.max()!.rounded(.up) - ys.min()!.rounded(.down)))
    let region = box.intersection(CGRect(origin: .zero, size: drawn.size)).integral
    return region.isNull || region.isEmpty ? CGRect(origin: .zero, size: drawn.size) : region
  }

  /// A drawing made on the framed picture (the size of the canvas) brought back to the start image's own coordinates, at
  /// `width × height`: the opposite of `frame`. What the canvas does not show stays transparent.
  public static func unframe(
    _ drawing: CGImage, canvasWidth: Int, canvasHeight: Int, framing: Framing, imageWidth: Int, imageHeight: Int,
    toWidth width: Int, height: Int
  ) -> PaintBitmap? {
    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0, canvasWidth > 0, canvasHeight > 0 else { return nil }
    let crop = FramingMath.cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: framing)
    let s = Double(canvasWidth) / crop.width
    let drawn = CGRect(
      x: -crop.minX * s, y: -(Double(imageHeight) - crop.maxY) * s, width: Double(imageWidth) * s,
      height: Double(imageHeight) * s)
    let angle = -framing.clamped().rotation * .pi / 180
    // Image (y up) → canvas, as `frame` draws it; the drawing goes the other way.
    let forward = CGAffineTransform(scaleX: s, y: s)
      .concatenating(CGAffineTransform(translationX: drawn.minX, y: drawn.minY))
      .concatenating(CGAffineTransform(translationX: -drawn.midX, y: -drawn.midY))
      .concatenating(CGAffineTransform(rotationAngle: angle))
      .concatenating(CGAffineTransform(translationX: drawn.midX, y: drawn.midY))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let done = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.interpolationQuality = .high
      context.scaleBy(x: Double(width) / Double(imageWidth), y: Double(height) / Double(imageHeight))
      context.concatenate(forward.inverted())
      context.draw(drawing, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
      return true
    }
    guard done else { return nil }
    return PaintBitmap.fromPremultiplied(bytes, width: width, height: height)
  }

  /// Turns what is drawn next about the centre of `drawn` (degrees, clockwise on the screen; Core Graphics counts
  /// angles the other way because its y axis points up).
  private static func turn(_ context: CGContext, about drawn: CGRect, rotation: Double) {
    guard rotation != 0 else { return }
    context.translateBy(x: drawn.midX, y: drawn.midY)
    context.rotate(by: -rotation * .pi / 180)
    context.translateBy(x: -drawn.midX, y: -drawn.midY)
  }

  /// The margins of a turned image: the picture is drawn turned on a transparent bitmap, and every pixel it does not
  /// cover takes the colour of the nearest one it does (two sweeps over the bitmap), so the corners continue the edges.
  private static func extendRotatedEdges(
    of image: CGImage, placed: CGRect, pivot: CGRect, rotation: Double, in context: CGContext, width: Int, height: Int
  ) {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let scratch = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      scratch.interpolationQuality = .high
      turn(scratch, about: pivot, rotation: rotation)
      scratch.draw(image, in: placed)
      return true
    }
    guard drew else { return }
    let count = width * height
    var nearest = [Int32](repeating: -1, count: count)
    var covered = 0
    for index in 0..<count where bytes[index * 4 + 3] == 255 {
      nearest[index] = Int32(index)
      covered += 1
    }
    guard covered > 0, covered < count else { return }
    func distance(_ from: Int, _ source: Int32) -> Int {
      let dx = from % width - Int(source) % width
      let dy = from / width - Int(source) / width
      return dx * dx + dy * dy
    }
    func relax(_ index: Int, _ neighbour: Int) {
      let source = nearest[neighbour]
      guard source >= 0 else { return }
      if nearest[index] < 0 || distance(index, source) < distance(index, nearest[index]) { nearest[index] = source }
    }
    for y in 0..<height {
      for x in 0..<width {
        let index = y * width + x
        if x > 0 { relax(index, index - 1) }
        if y > 0 {
          relax(index, index - width)
          if x > 0 { relax(index, index - width - 1) }
          if x < width - 1 { relax(index, index - width + 1) }
        }
      }
    }
    for y in stride(from: height - 1, through: 0, by: -1) {
      for x in stride(from: width - 1, through: 0, by: -1) {
        let index = y * width + x
        if x < width - 1 { relax(index, index + 1) }
        if y < height - 1 {
          relax(index, index + width)
          if x < width - 1 { relax(index, index + width + 1) }
          if x > 0 { relax(index, index + width - 1) }
        }
      }
    }
    var filled = [UInt8](repeating: 255, count: count * 4)
    for index in 0..<count {
      let source = Int(nearest[index])
      guard source >= 0 else { continue }
      // A covered pixel is opaque, so its colour is its own, not premultiplied.
      filled[index * 4] = bytes[source * 4]
      filled[index * 4 + 1] = bytes[source * 4 + 1]
      filled[index * 4 + 2] = bytes[source * 4 + 2]
    }
    guard let provider = CGDataProvider(data: Data(filled) as CFData),
      let background = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return }
    context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
  }

  /// Fills what the image leaves uncovered with its own edge pixels stretched outwards (and the corner
  /// pixels in the corners). The mask regenerates it anyway; this way the edge Draw Things blends
  /// back ("keep the original") carries the colours of the picture, not a stripe of grey. The corners
  /// go first, then the sides, each running one pixel under the image and into the corners, so a
  /// boundary that falls between pixels is covered whole by one strip and nothing shows through.
  private static func extendEdges(of image: CGImage, drawn: CGRect, in context: CGContext, width: Int, height: Int) {
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    guard !drawn.contains(canvas), image.width > 0, image.height > 0 else { return }
    let right = Double(width) - drawn.maxX
    let top = Double(height) - drawn.maxY
    let w = image.width
    let h = image.height
    func strip(_ x: Int, _ y: Int, _ cropWidth: Int, _ cropHeight: Int, into rect: CGRect) {
      guard rect.width > 0, rect.height > 0,
        let part = image.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight))
      else { return }
      context.draw(part, in: rect)
    }
    // Core Graphics counts from the bottom-left; the crops count from the top-left.
    if drawn.minX > 0 {
      if top > 0 { strip(0, 0, 1, 1, into: CGRect(x: 0, y: drawn.maxY, width: drawn.minX, height: top)) }
      if drawn.minY > 0 { strip(0, h - 1, 1, 1, into: CGRect(x: 0, y: 0, width: drawn.minX, height: drawn.minY)) }
    }
    if right > 0 {
      if top > 0 { strip(w - 1, 0, 1, 1, into: CGRect(x: drawn.maxX, y: drawn.maxY, width: right, height: top)) }
      if drawn.minY > 0 { strip(w - 1, h - 1, 1, 1, into: CGRect(x: drawn.maxX, y: 0, width: right, height: drawn.minY)) }
    }
    if drawn.minX > 0 {
      strip(0, 0, 1, h, into: CGRect(x: 0, y: drawn.minY - 1, width: drawn.minX + 1, height: drawn.height + 2))
    }
    if right > 0 {
      strip(w - 1, 0, 1, h, into: CGRect(x: drawn.maxX - 1, y: drawn.minY - 1, width: right + 1, height: drawn.height + 2))
    }
    if top > 0 {
      strip(0, 0, w, 1, into: CGRect(x: drawn.minX - 1, y: drawn.maxY - 1, width: drawn.width + 2, height: top + 1))
    }
    if drawn.minY > 0 {
      strip(0, h - 1, w, 1, into: CGRect(x: drawn.minX - 1, y: 0, width: drawn.width + 2, height: drawn.minY + 1))
    }
  }

  /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
  /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
  /// smoothing as the image and then cut at half, so its edge is clean at any scale. What the image
  /// does not cover (its margins in the canvas) is regenerated too, unless `marginsRegenerated` is false
  /// (a flat fill that an outpaint LoRA reads: the margins stay out of the mask); with no `mask` and the
  /// margins regenerated that is all.
  public static func mask(
    _ mask: MaskBitmap?, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing,
    marginsRegenerated: Bool = true
  ) -> CGImage? {
    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0 else { return nil }
    var gray: CGImage?
    if let mask {
      gray = mask.grayImage()
      if gray == nil { return nil }
    }
    let crop = FramingMath.cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
    var bytes = [UInt8](repeating: marginsRegenerated ? 255 : 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      let scale = Double(width) / crop.width
      // Where the image is: kept, unless the mask says otherwise.
      let drawn = CGRect(
        x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
        height: Double(imageHeight) * scale)
      context.setFillColor(gray: 0, alpha: 1)
      turn(context, about: drawn, rotation: framing.clamped().rotation)
      context.fill(drawn)
      if let gray { context.draw(gray, in: drawn) }
      return true
    }
    guard drawn else { return nil }
    // Transparent (0) where regenerated; black, premultiplied, so the colour channels stay 0.
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    for index in bytes.indices where bytes[index] < 128 { rgba[index * 4 + 3] = 255 }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
