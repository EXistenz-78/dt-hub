import Foundation

/// The box of an element on the 0…1000 grid of the caption, `[y0, x0, y1, x1]` (y first), origin at the top left.
struct BBox: Codable, Equatable, Sendable {
  var y0: Int
  var x0: Int
  var y1: Int
  var x1: Int

  static let grid = 1000
  /// The smallest side a box may have, on both axes.
  static let minSide = 20

  /// The box with its corners put in order and inside the grid; nil when a side is shorter than `minSide`.
  static func normalized(y0: Int, x0: Int, y1: Int, x1: Int) -> BBox? {
    func clamp(_ value: Int) -> Int { min(max(value, 0), grid) }
    let (a, b) = (clamp(min(y0, y1)), clamp(max(y0, y1)))
    let (c, d) = (clamp(min(x0, x1)), clamp(max(x0, x1)))
    guard b - a >= minSide, d - c >= minSide else { return nil }
    return BBox(y0: a, x0: c, y1: b, x1: d)
  }

  /// Four numbers written in any common way (`[10, 20, 300, 400]`, `10 20 300 400`, `100.5, 10, 300, 400`); decimals are
  /// rounded. Nil when they are not four numbers, or a side is too short.
  static func parse(_ text: String) -> BBox? {
    let tokens = text.split(whereSeparator: { !$0.isNumber && $0 != "-" && $0 != "." })
    let numbers = tokens.compactMap { Double($0) }
    guard numbers.count == 4, tokens.count == 4, numbers.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else { return nil }
    let whole = numbers.map { Int($0.rounded()) }
    return normalized(y0: whole[0], x0: whole[1], y1: whole[2], x1: whole[3])
  }

  /// Text in a position field that is not empty and still cannot be read as a position.
  static func isUnreadable(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parse(text) == nil
  }

  /// The box a position field holds after the user typed `text`: no text, no position; a readable one, that box; anything
  /// else (half typed, a side too short) leaves `current` as it was.
  static func resolve(_ text: String, current: BBox?) -> BBox? {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    return parse(text) ?? current
  }

  var array: [Int] { [y0, x0, y1, x1] }
  var text: String { "[\(y0), \(x0), \(y1), \(x1)]" }
}
