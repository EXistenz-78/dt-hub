import DTHubPluginKit
import Foundation

@testable import PromptMasterMing

final class MemoryStorage: SessionStorage, @unchecked Sendable {
  var values: [String: Data] = [:]
  func data(forKey key: String) -> Data? { values[key] }
  func set(_ data: Data, forKey key: String) { values[key] = data }
}

enum Fixture {
  static let data = MingData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))

  @MainActor
  static func state(size: PixelSize? = PixelSize(width: 832, height: 1248), storage: MemoryStorage = MemoryStorage()) -> MingState {
    let state = MingState(
      data: data,
      promptFolder: MingPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("ming-\(UUID().uuidString)")),
      store: MingStore(storage: storage), italian: false, shuffler: { _, _ in [] })
    state.active = true
    state.update(generationSize: size)
    return state
  }

  /// The README example of the ComfyUI node, with a background layer, in `json.dumps(indent=2, ensure_ascii=False)` form.
  static let golden = """
    {
      "canvas_settings": {
        "aspect_ratio": "2:3",
        "ambient_lighting": "soft studio lighting",
        "image_style": "modern editorial poster"
      },
      "layers": [
        {
          "description": "A solid cream background.",
          "coordinates": "cx: 0.500, cy: 0.500, w: 1.000, h: 1.000",
          "hierarchy_and_relation": "",
          "color_specs": []
        },
        {
          "description": "A text element reading exactly \\"FUTURE MEMORY\\" in condensed white typography.",
          "coordinates": "cx: 0.500, cy: 0.120, w: 0.800, h: 0.140",
          "hierarchy_and_relation": "Primary headline above the central subject.",
          "color_specs": [
            "#FFFFFF"
          ]
        }
      ]
    }
    """

  /// A prompt in the style of DT Hub's Ming Family prompt: pixel aspect ratio, quoted words inside prose.
  static let familyStyle = """
    {"canvas_settings": {"aspect_ratio": "landscape, 1248 x 832 px", "ambient_lighting": "bright daylight", "image_style": "flat vector poster"},
     "layers": [
      {"description": "A flat orange background filling the canvas.", "coordinates": "cx: 0.500, cy: 0.500, w: 1.000, h: 1.000", "hierarchy_and_relation": "Base layer.", "color_specs": ["#ff8800"]},
      {"description": "Bold white condensed headline \\"SUMMER SALE\\" with a soft shadow.", "coordinates": "cx: 0.500, cy: 0.200, w: 0.700, h: 0.150", "hierarchy_and_relation": "Above the product.", "color_specs": ["#FFFFFF", "not a color"]},
      {"description": "A glass bottle of lemonade with ice.", "coordinates": "cx: 0.5, cy: 0.6, w: 0.3, h: 0.5"}
     ]}
    """
}
