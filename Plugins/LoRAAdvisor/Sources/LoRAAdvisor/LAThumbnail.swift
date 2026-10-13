import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The thumbnails of the LoRAs: whatever picture comes in is decoded and written again as a small JPEG, so what was
/// downloaded never stays on the disk as it came.
enum LAThumbnail {
  /// A JPEG no larger than `maxPixel` on its long side (the first frame of an animation); nil when the data is not a
  /// picture.
  static func jpeg(from data: Data, maxPixel: Int = 256) -> Data? {
    guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
  }
}
