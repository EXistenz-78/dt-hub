import Foundation

/// The bodies of the `contribute` messages (contract 1, `PluginKit/README.md`).
enum CSMessages {
  /// All three kinds of sheet use the same canvas: 4:3 landscape, both sides multiples of 64. 2048 is the widest
  /// canvas the app takes without tiled diffusion (a wider one is cut to it, as a first try with 2304 showed).
  static let width = 2048
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
