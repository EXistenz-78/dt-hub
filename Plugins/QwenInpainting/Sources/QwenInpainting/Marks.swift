import CoreGraphics
import Foundation

enum MarkTool: String, Codable, CaseIterable { case sketch, box, circle, arrow }

/// The colours of the marks: pure colours, so that the model can tell them apart. The English name goes into the prompt.
enum MarkColor: String, Codable, CaseIterable {
  case yellow, red, blue, cyan, magenta, green, purple, white, black

  var rgb: (UInt8, UInt8, UInt8) {
    switch self {
    case .yellow: (255, 255, 0)
    case .red: (255, 0, 0)
    case .blue: (0, 0, 255)
    case .cyan: (0, 255, 255)
    case .magenta: (255, 0, 255)
    case .green: (0, 255, 0)
    case .purple: (128, 0, 255)
    case .white: (255, 255, 255)
    case .black: (0, 0, 0)
    }
  }
}

/// One mark drawn on the start image. All the coordinates are fractions of the image (0…1).
struct Mark: Codable, Equatable {
  static let widthRange = 4.0...128.0
  static let defaultWidth = 16.0
  static let maxPoints = 4_000
  static let maxMarks = 200

  var tool: MarkTool
  var color: MarkColor
  /// Line width in pixels of the start image.
  var width: Double
  /// box/circle: two opposite corners; arrow: tail and tip; sketch: the stroke.
  var points: [CGPoint]

  init(tool: MarkTool, color: MarkColor, width: Double = Mark.defaultWidth, points: [CGPoint]) {
    self.tool = tool
    self.color = color
    self.width = width
    self.points = points
  }

  /// The points brought into 0…1 (at most `maxPoints`) and the width into its range.
  func clamped() -> Mark {
    Mark(
      tool: tool, color: color, width: min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound),
      points: points.prefix(Self.maxPoints).map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) })
  }
}

/// One card of text for each pair of colour and tool.
struct CardKey: Hashable, Codable {
  var color: MarkColor
  var tool: MarkTool

  var rawValue: String { "\(color.rawValue):\(tool.rawValue)" }

  init(color: MarkColor, tool: MarkTool) {
    self.color = color
    self.tool = tool
  }

  init?(rawValue: String) {
    let parts = rawValue.split(separator: ":").map(String.init)
    guard parts.count == 2, let color = MarkColor(rawValue: parts[0]), let tool = MarkTool(rawValue: parts[1]) else { return nil }
    self.init(color: color, tool: tool)
  }
}
