import Foundation

/// The words of the tab (English, like the other plug-ins' interface).
enum L {
  static let title = "Seamless Pattern"
  static let repeatTitle = "Repeat"
  static let both = "Both"
  static let leftRight = "Left-right"
  static let upDown = "Up-down"
  static let prepare = "Prepare Run · Seamless"
  static let stop = "Stop seamless"
  static let prepared = "Ready: press Run (it says “Run · Seamless”)."
  static let lastResult = "Last result"
  static let dropped = "Dropped image"
  static let noImage = "No picture yet. Run, or drop an image here."
  static let view = "View"
  static let seam = "Seam"
  static let savePNG = "Save PNG…"
  static let showInFinder = "Show in Finder"
  static let saved = "Saved."
  static let saveFailed = "Could not save the PNG."
  static let unsupportedFamily = "This model family is not supported."
  static let notAnswered = "No answer from the app."

  static func mode(_ mode: SPMode) -> String {
    switch mode {
    case .both: both
    case .leftRight: leftRight
    case .upDown: upDown
    }
  }

  static func view(_ view: SPView) -> String {
    switch view {
    case .tile: "Tile"
    case .twoByTwo: "2×2"
    case .threeByThree: "3×3"
    case .offset: "Offset"
    case .halfDrop: "Half-drop"
    case .halfBrick: "Half-brick"
    }
  }
}
