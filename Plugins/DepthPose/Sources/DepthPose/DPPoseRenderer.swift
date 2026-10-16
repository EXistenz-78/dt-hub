import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the OpenPose picture: black background, one coloured bone for each pair of joints, a dot on each joint.
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

  /// The picture of the people, or nil when no one has a bone to draw.
  static func render(_ people: [DPPerson], width: Int, height: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let drawn = people.filter { !DPSkeleton.drawableBones(of: $0).isEmpty }
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
    for person in drawn {
      let points = DPSkeleton.points(of: person)
      for (index, bone) in DPSkeleton.bones.enumerated() {
        guard let a = points[bone.0], let b = points[bone.1] else { continue }
        context.setStrokeColor(colour(index, shade: boneShade))
        context.move(to: pixel(a))
        context.addLine(to: pixel(b))
        context.strokePath()
      }
    }
    for person in drawn {
      for (joint, point) in DPSkeleton.points(of: person) {
        let centre = pixel(point)
        context.setFillColor(colour(joint.rawValue, shade: 1))
        context.fillEllipse(in: CGRect(x: centre.x - size, y: centre.y - size, width: size * 2, height: size * 2))
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
