import Foundation

/// The bodies of the `contribute` messages (contract 1, `PluginKit/README.md`).
enum CSMessages {
  /// The sheet is a 3:2 landscape; both sides are multiples of 64 (the size the Draw Things canvas takes).
  static let width = 2304
  static let height = 1536
  /// The picture copied into the app's temporary folder keeps this name, so a second run replaces the first.
  static let referenceFileStem = "com.exiztenz.dthub.charactersheet-reference"

  static func moodboard(imagePath: String) -> [String: Any] {
    ["moodboard": [["path": imagePath, "name": "Character reference"]]]
  }

  static func size() -> [String: Any] {
    ["fields": ["width": width, "height": height]]
  }

  static func prompt(_ text: String) -> [String: Any] {
    ["fields": ["prompt": text]]
  }
}
