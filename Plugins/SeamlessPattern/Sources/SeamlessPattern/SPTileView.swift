import CoreGraphics

enum SPView: String, CaseIterable, Codable, Sendable {
  case tile, twoByTwo, threeByThree, offset
}

/// Port of `tile_view` of `_seamless_helpers.py`: the pattern laid out the way the view shows it. Tile = the picture
/// itself; 2x2 / 3x3 = repeats; Offset = moved by half a tile both ways (the four corners meet in the middle). The node's
/// Half-drop and Half-brick views are left out.
enum SPTileView {
  static func render(_ image: CGImage, view: SPView) -> CGImage? {
    guard let p = SPPixels(image) else { return nil }
    let w = p.width, h = p.height
    switch view {
    case .tile: return p.cgImage()
    case .twoByTwo: return build(p, outW: 2 * w, outH: 2 * h) { x, y in (x % w, y % h) }
    case .threeByThree: return build(p, outW: 3 * w, outH: 3 * h) { x, y in (x % w, y % h) }
    case .offset:
      // torch.roll(shifts=(h // 2, w // 2)): out[y][x] = in[(y - h // 2) mod h][(x - w // 2) mod w].
      return build(p, outW: w, outH: h) { x, y in (mod(x - w / 2, w), mod(y - h / 2, h)) }
    }
  }

  private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

  private static func build(_ p: SPPixels, outW: Int, outH: Int, source: (Int, Int) -> (Int, Int)) -> CGImage? {
    var out = [UInt8](repeating: 255, count: outW * outH * 4)
    for y in 0..<outH {
      for x in 0..<outW {
        let (sx, sy) = source(x, y)
        let s = (sy * p.width + sx) * 4, d = (y * outW + x) * 4
        out[d] = p.rgba[s]
        out[d + 1] = p.rgba[s + 1]
        out[d + 2] = p.rgba[s + 2]
      }
    }
    return SPPixels(width: outW, height: outH, rgba: out).cgImage()
  }
}
