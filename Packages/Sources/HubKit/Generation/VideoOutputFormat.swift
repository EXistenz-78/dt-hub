import Foundation

/// A standard video format. Draw Things wants sides in multiples of 64, which these are not: the clip is generated
/// at the exact size rounded up (`generatedWidth` × `generatedHeight`) and every frame is cropped, centered, to
/// the exact size when the MP4 is made.
public struct VideoOutputFormat: Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  /// The technical name shown in the menu (not translated).
  public let name: String
  public let width: Int
  public let height: Int

  public var generatedWidth: Int { Self.roundedUp(width) }
  public var generatedHeight: Int { Self.roundedUp(height) }

  /// The longest side of the generated size: what the size limit is checked against.
  public var generatedLongSide: Int { max(generatedWidth, generatedHeight) }

  public static let all: [VideoOutputFormat] = [
    VideoOutputFormat(id: "480p", name: "480p", width: 640, height: 480),
    VideoOutputFormat(id: "ntsc", name: "NTSC", width: 720, height: 480),
    VideoOutputFormat(id: "pal", name: "PAL", width: 720, height: 576),
    VideoOutputFormat(id: "720p", name: "720p", width: 1280, height: 720),
    VideoOutputFormat(id: "1080p", name: "1080p", width: 1920, height: 1080),
    VideoOutputFormat(id: "2k-dci", name: "2K DCI", width: 2048, height: 1080),
    VideoOutputFormat(id: "1440p", name: "1440p", width: 2560, height: 1440),
    VideoOutputFormat(id: "4k-uhd", name: "4K UHD", width: 3840, height: 2160),
    VideoOutputFormat(id: "4k-dci", name: "4K DCI", width: 4096, height: 2160),
    VideoOutputFormat(id: "8k-uhd", name: "8K UHD", width: 7680, height: 4320),
  ]

  /// A side rounded up to the next multiple of 64.
  public static func roundedUp(_ side: Int) -> Int {
    (max(side, 1) + 63) / 64 * 64
  }

  /// Whether the generated size fits the current size limit (2048, or 8192 with HiRes or Tiled Diffusion).
  public func isAvailable(sizeLimit: Int) -> Bool {
    generatedLongSide <= sizeLimit
  }

  /// The formats that fit the size limit.
  public static func available(sizeLimit: Int) -> [VideoOutputFormat] {
    all.filter { $0.isAvailable(sizeLimit: sizeLimit) }
  }

  /// The format of an exact size, landscape or swapped (portrait).
  public static func matching(outputWidth: Int, outputHeight: Int) -> VideoOutputFormat? {
    all.first {
      ($0.width == outputWidth && $0.height == outputHeight) || ($0.width == outputHeight && $0.height == outputWidth)
    }
  }
}
