import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the OpenPose picture: black background, one coloured bone for each pair of joints, a dot on each joint; and,
/// when the figure has them, the hands (coloured edges, blue points) and the face (white dots) of the DWPose picture.
enum DPPoseRenderer {
  /// The 18 colours of OpenPose (RGB). Bone *i* of `DPSkeleton.bones` and the joint of index *i* use colour *i*.
  static let colors: [(UInt8, UInt8, UInt8)] = [
    (255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85),
    (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255), (170, 0, 255),
    (255, 0, 255), (255, 0, 170), (255, 0, 85),
  ]

  /// Bones are drawn at this share of their colour, as in the pictures ControlNet models are trained on.
  static let boneShade = 0.6

  /// The width of a bone and the radius of a joint, in pixels.
  static func thickness(forLongSide side: Int) -> Int { max(3, side / 170) }

  /// The 20 edges of a hand of 21 points (the wrist is point 0, then four points for each finger).
  static let handEdges: [(Int, Int)] = [
    (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (0, 9), (9, 10), (10, 11), (11, 12), (0, 13),
    (13, 14), (14, 15), (15, 16), (0, 17), (17, 18), (18, 19), (19, 20),
  ]

  /// The RGB of a hue (0–1) at full saturation and value, as `matplotlib.colors.hsv_to_rgb` gives it.
  static func hsv(_ hue: Double) -> (UInt8, UInt8, UInt8) {
    let scaled = (hue - hue.rounded(.down)) * 6
    let sector = Int(scaled.rounded(.down)) % 6
    let f = scaled - scaled.rounded(.down)
    let (r, g, b): (Double, Double, Double)
    switch sector {
    case 0: (r, g, b) = (1, f, 0)
    case 1: (r, g, b) = (1 - f, 1, 0)
    case 2: (r, g, b) = (0, 1, f)
    case 3: (r, g, b) = (0, 1 - f, 1)
    case 4: (r, g, b) = (f, 0, 1)
    default: (r, g, b) = (1, 0, 1 - f)
    }
    return (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
  }

  /// A figure is drawn when it has a bone of the body, or a face with at least 10 points, or a hand with at least 5
  /// (counting the points above the confidence threshold).
  static func isDrawable(_ figure: DPFigure) -> Bool {
    func usable(_ points: [DPPoint]) -> Int { points.filter { $0.confidence >= DPSkeleton.minConfidence }.count }
    if !DPSkeleton.drawableBones(of: figure.body).isEmpty { return true }
    return usable(figure.face) >= 10 || usable(figure.leftHand) >= 5 || usable(figure.rightHand) >= 5
  }

  /// The picture of the people (body only), or nil when no one has a bone to draw.
  static func render(_ people: [DPPerson], width: Int, height: Int) -> CGImage? {
    render(people.map { DPFigure(body: $0) }, width: width, height: height)
  }

  /// The picture of the figures, or nil when none of them can be drawn.
  static func render(_ figures: [DPFigure], width: Int, height: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let drawn = figures.filter(isDrawable)
    guard !drawn.isEmpty, width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    // Row 0 at the top, like the points.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    // `CGColor(red:green:blue:alpha:)` is in the generic RGB space, which would shift the values: use the context's.
    context.setFillColor(CGColor(colorSpace: space, components: [0, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setShouldAntialias(true)

    let size = CGFloat(thickness(forLongSide: max(width, height)))
    func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height)) }
    func colour(_ index: Int, shade: Double) -> CGColor {
      let c = colors[index]
      let components = [CGFloat(c.0), CGFloat(c.1), CGFloat(c.2)].map { $0 / 255 * CGFloat(shade) } + [1]
      return CGColor(colorSpace: space, components: components)!
    }

    context.setLineWidth(size)
    context.setLineCap(.round)
    for figure in drawn {
      let points = DPSkeleton.points(of: figure.body)
      for (index, bone) in DPSkeleton.bones.enumerated() {
        guard let a = points[bone.0], let b = points[bone.1] else { continue }
        context.setStrokeColor(colour(index, shade: boneShade))
        context.move(to: pixel(a))
        context.addLine(to: pixel(b))
        context.strokePath()
      }
    }
    func dot(_ centre: CGPoint, radius: CGFloat) {
      context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
    for figure in drawn {
      for (joint, point) in DPSkeleton.points(of: figure.body) {
        context.setFillColor(colour(joint.rawValue, shade: 1))
        dot(pixel(point), radius: size)
      }
    }

    // The hands: edges in the colour of their hue, then blue points on top of them.
    func usable(_ point: DPPoint) -> Bool { point.confidence >= DPSkeleton.minConfidence }
    let hands = drawn.flatMap { [$0.leftHand, $0.rightHand] }.filter { $0.count == 21 }
    context.setLineWidth(max(2, (size / 2).rounded()))
    for hand in hands {
      for (index, edge) in handEdges.enumerated() where usable(hand[edge.0]) && usable(hand[edge.1]) {
        let rgb = hsv(Double(index) / Double(handEdges.count))
        context.setStrokeColor(
          CGColor(colorSpace: space, components: [CGFloat(rgb.0) / 255, CGFloat(rgb.1) / 255, CGFloat(rgb.2) / 255, 1])!)
        context.move(to: pixel(CGPoint(x: hand[edge.0].x, y: hand[edge.0].y)))
        context.addLine(to: pixel(CGPoint(x: hand[edge.1].x, y: hand[edge.1].y)))
        context.strokePath()
      }
    }
    context.setFillColor(CGColor(colorSpace: space, components: [0, 0, 1, 1])!)
    for hand in hands {
      for point in hand where usable(point) { dot(pixel(CGPoint(x: point.x, y: point.y)), radius: size) }
    }

    // The face: white dots over everything else.
    context.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    for figure in drawn {
      for point in figure.face where usable(point) {
        dot(pixel(CGPoint(x: point.x, y: point.y)), radius: max(2, (size * 0.75).rounded()))
      }
    }
    return context.makeImage()
  }

  static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
