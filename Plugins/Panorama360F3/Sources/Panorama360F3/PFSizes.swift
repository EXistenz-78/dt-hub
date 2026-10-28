import Foundation

/// The sizes the plug-in offers: always 2:1, the height a multiple of 64, in steps of +128 × +64 from 1024×512 to 8192×4096 (57 sizes).
enum PFSizes {
  static let standard = PFSize(width: 2048, height: 1024)
  static let minimum = PFSize(width: 1024, height: 512)
  static let maximum = PFSize(width: 8192, height: 4096)
  private static let stepWidth = 128
  private static let stepHeight = 64

  /// True when the size is one of the ladder's steps.
  static func isValid(_ size: PFSize) -> Bool {
    size.width >= minimum.width && size.width <= maximum.width && (size.width - minimum.width) % stepWidth == 0
      && size.height == size.width / 2
  }

  /// The next size up, nil at the maximum (or for a size that is not on the ladder).
  static func larger(_ size: PFSize) -> PFSize? {
    guard isValid(size), size != maximum else { return nil }
    return PFSize(width: size.width + stepWidth, height: size.height + stepHeight)
  }

  /// The next size down, nil at the minimum (or for a size that is not on the ladder).
  static func smaller(_ size: PFSize) -> PFSize? {
    guard isValid(size), size != minimum else { return nil }
    return PFSize(width: size.width - stepWidth, height: size.height - stepHeight)
  }
}
