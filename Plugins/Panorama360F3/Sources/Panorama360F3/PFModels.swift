import Foundation

/// One reference picture of the Moodboard. `file` is relative to the project folder.
struct PFImage: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var name: String
  var file: String
  var visible = true
}

/// A panorama size in pixels.
struct PFSize: Codable, Equatable, Sendable {
  var width: Int
  var height: Int
}

/// What the plug-in remembers for a project (`state.json`). The order of `images` is the order of `<image N>`; only the visible ones are sent and numbered.
struct PanoState: Codable, Equatable, Sendable {
  static let currentVersion = 1
  static let fileName = "state.json"

  var version = PanoState.currentVersion
  var images: [PFImage] = []
  var description = ""
  var size = PFSize(width: 2048, height: 1024)
  var viewerOpen = false

  init() {}

  /// Lenient: a key that is missing keeps its default.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? PanoState.currentVersion
    images = try container.decodeIfPresent([PFImage].self, forKey: .images) ?? []
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    size = try container.decodeIfPresent(PFSize.self, forKey: .size) ?? PFSize(width: 2048, height: 1024)
    viewerOpen = try container.decodeIfPresent(Bool.self, forKey: .viewerOpen) ?? false
  }
}
