import CoreGraphics
import Foundation

/// A rectangle in whole pixels of an image, origin at the top left.
public struct PixelRect: Equatable, Codable, Sendable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// What the Control tab keeps while a crop of the start image is being retouched: the crop, the
/// original image to put the result back into, and the tab's settings and generation size from
/// before the crop, so they can be restored afterwards.
public struct LocalEditSession: Equatable, Codable, Sendable {
  public let id: UUID
  /// The crop, in pixels of the original.
  public let rect: PixelRect
  /// The whole image the crop was taken from.
  public let original: ReferenceImage
  public let framing: Framing
  public let mask: MaskReference?
  public let paint: PaintReference?
  public let strength: Double?
  public let marginFill: MarginFill?
  public let generationWidth: Int
  public let generationHeight: Int
  public let generationHighRes: Bool
  public let openedAt: Date
  /// Whether the retouched crop is colour-matched to the original when it is put back.
  public var matchColors: Bool

  public init(
    id: UUID, rect: PixelRect, original: ReferenceImage, framing: Framing, mask: MaskReference?,
    paint: PaintReference?, strength: Double?, marginFill: MarginFill?, generationWidth: Int,
    generationHeight: Int, generationHighRes: Bool, openedAt: Date, matchColors: Bool = true
  ) {
    self.id = id
    self.rect = rect
    self.original = original
    self.framing = framing
    self.mask = mask
    self.paint = paint
    self.strength = strength
    self.marginFill = marginFill
    self.generationWidth = generationWidth
    self.generationHeight = generationHeight
    self.generationHighRes = generationHighRes
    self.openedAt = openedAt
    self.matchColors = matchColors
  }
}
