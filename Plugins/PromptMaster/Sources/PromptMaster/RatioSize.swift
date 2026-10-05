import Foundation

/// From the format a prompt enhancer suggests ("3:2") to a size for the Generation tab (spec §7).
enum RatioSize {
  /// Draw Things works in multiples of 64.
  static let step = 64
  static let limits = 64...4096

  /// `"3:2"` → (3, 2). Whole numbers above zero on both sides of one colon; spaces around them do not matter.
  static func parse(_ ratio: String) -> (width: Int, height: Int)? {
    let parts = ratio.split(separator: ":", omittingEmptySubsequences: false).map {
      Int($0.trimmingCharacters(in: .whitespaces))
    }
    guard parts.count == 2, let width = parts[0], let height = parts[1], width > 0, height > 0 else { return nil }
    return (width, height)
  }

  /// The size with that ratio and the same area in pixels as `area`, each side rounded to the nearest multiple of 64
  /// and kept between 64 and 4096. Nil when the ratio cannot be read or there is no area.
  static func size(ratio: String, area: Int) -> (width: Int, height: Int)? {
    guard let parts = parse(ratio), area > 0 else { return nil }
    let r = Double(parts.width) / Double(parts.height)
    func snap(_ side: Double) -> Int {
      min(max(Int((side / Double(step)).rounded()) * step, limits.lowerBound), limits.upperBound)
    }
    return (snap((Double(area) * r).squareRoot()), snap((Double(area) / r).squareRoot()))
  }

  /// The size the app says the Generation tab has now, from the `context` message (`parameters.width` and `.height`).
  static func currentSize(inContext data: Data) -> (width: Int, height: Int)? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let parameters = object["parameters"] as? [String: Any],
      let width = parameters["width"] as? Int, let height = parameters["height"] as? Int, width > 0, height > 0
    else { return nil }
    return (width, height)
  }
}
