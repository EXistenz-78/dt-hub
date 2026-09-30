/// An aspect ratio in landscape form (width ≥ height); the swap button gives the portrait one.
public struct AspectRatio: Equatable, Hashable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  /// "16:9". Technical, the same in every language.
  public var label: String { "\(width):\(height)" }

  /// Width ÷ height.
  public var value: Double { Double(width) / Double(height) }

  public static let presets: [AspectRatio] = [
    AspectRatio(width: 1, height: 1), AspectRatio(width: 5, height: 4), AspectRatio(width: 4, height: 3),
    AspectRatio(width: 3, height: 2), AspectRatio(width: 2, height: 1), AspectRatio(width: 16, height: 9),
  ]
}
