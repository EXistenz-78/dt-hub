import CoreGraphics
import Foundation
import HubKit

/// The pictures side of local editing: cuts the crop out of a start image (and of its smaller
/// mask or drawing), and puts a retouched crop back into the whole image, matching its colours
/// to the surroundings and softening the inner edge.
public enum LocalEditCompositor {
  /// The part of `image` inside `rect` (pixel for pixel), as an opaque sRGB 8-bit picture.
  /// Nil if the rectangle is empty or not inside the image.
  public static func crop(_ image: CGImage, to rect: PixelRect) -> CGImage? {
    guard rect.width > 0, rect.height > 0, rect.x >= 0, rect.y >= 0,
      rect.x + rect.width <= image.width, rect.y + rect.height <= image.height,
      let part = image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
    else { return nil }
    guard let context = makeContext(width: rect.width, height: rect.height) else { return nil }
    context.draw(part, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    return context.makeImage()
  }

  /// The same area for a picture saved smaller than the full image (a mask, a drawing):
  /// the rectangle is scaled by `image.width / fullWidth` and `image.height / fullHeight`.
  public static func crop(_ image: CGImage, to rect: PixelRect, fullWidth: Int, fullHeight: Int)
    -> CGImage?
  {
    guard fullWidth > 0, fullHeight > 0 else { return nil }
    let sx = Double(image.width) / Double(fullWidth)
    let sy = Double(image.height) / Double(fullHeight)
    let x0 = Int((Double(rect.x) * sx).rounded())
    let y0 = Int((Double(rect.y) * sy).rounded())
    let x1 = Int((Double(rect.x + rect.width) * sx).rounded())
    let y1 = Int((Double(rect.y + rect.height) * sy).rounded())
    return crop(image, to: PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
  }

  /// `original` with `retouch` put over `rect`. With `matchColors` the retouch is first
  /// brought, per channel, to the level of the original along the four inner edges; the
  /// outer band of the rectangle fades into the original. Nil if `retouch` is not exactly
  /// `rect.width × rect.height` or the rectangle is not inside the original.
  public static func montage(
    original: CGImage, retouch: CGImage, rect: PixelRect, matchColors: Bool
  ) -> CGImage? {
    let w = rect.width, h = rect.height
    guard w > 0, h > 0, retouch.width == w, retouch.height == h,
      rect.x >= 0, rect.y >= 0, rect.x + w <= original.width, rect.y + h <= original.height,
      let out = makeContext(width: original.width, height: original.height),
      let patch = makeContext(width: w, height: h),
      let outData = out.data, let patchData = patch.data
    else { return nil }
    out.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
    patch.draw(retouch, in: CGRect(x: 0, y: 0, width: w, height: h))

    let outStride = out.bytesPerRow, patchStride = patch.bytesPerRow
    let o = outData.assumingMemoryBound(to: UInt8.self)
    let p = patchData.assumingMemoryBound(to: UInt8.self)
    let band = min(LocalEditMath.featherWidth(for: rect), max(1, min(w, h) / 2))

    // Gains per side and channel; 1 when colours are not matched.
    var top = [Double](repeating: 1, count: 3), bottom = top, left = top, right = top
    if matchColors {
      func gains(_ xs: Range<Int>, _ ys: Range<Int>) -> [Double] {
        var so = [Double](repeating: 0, count: 3), sp = so
        for y in ys {
          for x in xs {
            let io = (rect.y + y) * outStride + (rect.x + x) * 4
            let ip = y * patchStride + x * 4
            for c in 0..<3 {
              so[c] += Double(o[io + c])
              sp[c] += Double(p[ip + c])
            }
          }
        }
        let n = Double(xs.count * ys.count)
        return (0..<3).map { c in
          min(5, max(0.2, (so[c] / n + 1) / (sp[c] / n + 1)))
        }
      }
      top = gains(0..<w, 0..<band)
      bottom = gains(0..<w, (h - band)..<h)
      left = gains(0..<band, 0..<h)
      right = gains((w - band)..<w, 0..<h)
    }

    // Per-column and per-row parts of the gain, so the pixel loop only adds. Fixed-point
    // (1/1024) integers keep the loop cheap.
    var colGain = [Int32](repeating: 1024, count: w * 3)
    for x in 0..<w {
      let u = (Double(x) + 0.5) / Double(w)
      for c in 0..<3 { colGain[x * 3 + c] = Int32((((1 - u) * left[c] + u * right[c]) * 512).rounded()) }
    }
    colGain.withUnsafeBufferPointer { col in
      for y in 0..<h {
        let v = (Double(y) + 0.5) / Double(h)
        let r0 = Int32((((1 - v) * top[0] + v * bottom[0]) * 512).rounded())
        let r1 = Int32((((1 - v) * top[1] + v * bottom[1]) * 512).rounded())
        let r2 = Int32((((1 - v) * top[2] + v * bottom[2]) * 512).rounded())
        let dy = min(y, h - 1 - y)
        let outRow = o + (rect.y + y) * outStride + rect.x * 4
        let patchRow = p + y * patchStride
        for x in 0..<w {
          let d = min(dy, min(x, w - 1 - x))
          if d == 0 { continue }
          let weight = d >= band ? Int32(256) : Int32(d * 256 / band)
          let po = outRow + x * 4, pp = patchRow + x * 4
          for c in 0..<3 {
            var value = Int32(pp[c])
            if matchColors {
              let g = (c == 0 ? r0 : c == 1 ? r1 : r2) + col[x * 3 + c]  // gain × 1024
              value = min(255, max(0, (((value + 1) * g + 512) >> 10) - 1))
            }
            if weight == 256 {
              po[c] = UInt8(value)
            } else {
              let base = Int32(po[c])
              po[c] = UInt8(base + ((value - base) * weight + (value >= base ? 128 : -128)) / 256)
            }
          }
        }
      }
    }
    return out.makeImage()
  }

  /// An sRGB RGBA 8-bit context whose pixels are opaque; its memory starts with the top row.
  private static func makeContext(width: Int, height: Int) -> CGContext? {
    guard width > 0, height > 0 else { return nil }
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    context?.interpolationQuality = .high
    return context
  }
}
