import CoreGraphics
import Foundation

/// 8-bit RGBA pixels of a picture (alpha is carried along but never read by the seam check).
struct SPPixels {
  var width: Int
  var height: Int
  var rgba: [UInt8]

  init(width: Int, height: Int, rgba: [UInt8]) {
    self.width = width
    self.height = height
    self.rgba = rgba
  }

  /// Draws the picture into an sRGB 8-bit RGBA buffer. For a picture already in sRGB (what DT Hub makes) the bytes are
  /// the picture's own values; alpha is ignored (the buffer is opaque), like the node's `image[..., :3]`.
  init?(_ image: CGImage) {
    let w = image.width, h = image.height
    guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { return false }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard ok else { return nil }
    self.init(width: w, height: h, rgba: bytes)
  }

  func cgImage() -> CGImage? {
    guard width > 0, height > 0, rgba.count == width * height * 4, let space = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(rgba) as CFData)
    else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent)
  }
}

enum SPSeamStatus: String, Codable, Sendable { case pass, warn, fail, notApplicable }

struct SPSeamResult: Codable, Equatable, Sendable {
  var status: SPSeamStatus
  /// The wrap line's score over the median inner line (1.0 = a normal line); nil = no normal line to compare with.
  var ratio: Double?
  /// The share of inner lines that are worse than the wrap line.
  var rank: Double?
  /// The wrap line's score over the worst inner line.
  var vsWorst: Double?
}

/// Port of `seam_check` / `_boundary_scores` of `_seamless_helpers.py` (Seamless Tile node), same constants: the jump
/// across the wrap line is compared with the jumps across the lines inside the picture, every `step` px.
enum SPSeam {
  static let step = 4
  static let warnFactor = 1.25
  static let minSize = 64

  static func check(_ image: CGImage) -> (leftRight: SPSeamResult, upDown: SPSeamResult) {
    // The node works on float values 0...1; 8-bit value / 255 is exactly what ComfyUI's loaders give.
    guard let p = SPPixels(image) else {
      let na = SPSeamResult(status: .notApplicable)
      return (na, na)
    }
    return (
      score(p, horizontal: true),
      score(p, horizontal: false)
    )
  }

  /// `horizontal` = the left-right direction (axis -1 of the node: the line index is the column).
  private static func score(_ p: SPPixels, horizontal: Bool) -> SPSeamResult {
    let n = horizontal ? p.width : p.height
    guard n >= max(minSize, step * 4) else { return SPSeamResult(status: .notApplicable) }
    let other = horizontal ? p.height : p.width
    // per[i] = mean over the channels and the other axis of |pixel(i) - pixel(i - 1)| (roll by 1: index 0 = wrap line).
    var per = [Double](repeating: 0, count: n)
    for i in 0..<n {
      let prev = (i + n - 1) % n
      var sum = 0.0
      for j in 0..<other {
        let a = horizontal ? (j * p.width + i) * 4 : (i * p.width + j) * 4
        let b = horizontal ? (j * p.width + prev) * 4 : (prev * p.width + j) * 4
        for c in 0..<3 { sum += abs(Double(p.rgba[a + c]) - Double(p.rgba[b + c])) }
      }
      per[i] = sum / 255 / Double(3 * other)
    }
    // Score of every line at a multiple of `step`: its jump over the mean jump across the two lines next to it.
    var scores: [Double] = []
    for idx in stride(from: 0, to: n, by: step) {
      let near = 0.5 * (per[(idx + n - 1) % n] + per[(idx + 1) % n])
      scores.append(per[idx] / max(near, 1e-6))
    }
    let seam = scores[0]
    let others = Array(scores.dropFirst())
    guard let worst = others.max() else { return SPSeamResult(status: .notApplicable) }
    let rank = Double(others.filter { $0 > seam }.count) / Double(others.count)
    // torch.median: the lower of the two middle values for an even count.
    let sorted = others.sorted()
    let median = sorted[(sorted.count - 1) / 2]
    let ratio: Double? = median > 1e-6 ? rounded(seam / median) : nil
    let status: SPSeamStatus
    if seam <= worst * (1 + 1e-6) + 1e-6 {
      status = .pass
    } else if seam <= worst * warnFactor {
      status = .warn
    } else {
      status = .fail
    }
    return SPSeamResult(status: status, ratio: ratio, rank: rounded(rank), vsWorst: rounded(seam / max(worst, 1e-6)))
  }

  private static func rounded(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

extension SPSeamResult {
  init(status: SPSeamStatus) { self.init(status: status, ratio: nil, rank: nil, vsWorst: nil) }
}
