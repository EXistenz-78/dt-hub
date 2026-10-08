import Foundation
import HubKit
import Testing

@testable import LLMBridge

/// Qwen's prompt enhancers ship a `processor_config.json` in the newer Transformers layout: the image settings sit under
/// `image_processor`. mlx-swift-lm reads them at the top level (the old `preprocessor_config.json` layout).
struct ProcessorConfigFixTests {
  static let nested = """
    {
      "image_processor": {
        "do_convert_rgb": true, "do_normalize": true, "do_rescale": true,
        "image_mean": [0.5, 0.5, 0.5], "image_std": [0.5, 0.5, 0.5],
        "image_processor_type": "Qwen3VLImageProcessor",
        "max_pixels": 16777216, "min_pixels": 65536, "merge_size": 2, "patch_size": 16,
        "rescale_factor": 0.00392156862745098, "temporal_patch_size": 2
      },
      "processor_class": "Qwen3VLProcessor",
      "video_processor": { "fps": 2.0 }
    }
    """

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pcf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func object(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func theImageSettingsMoveToTheTopLevel() throws {
    let flat = try object(ProcessorConfigFix.flattened(Data(Self.nested.utf8)))
    #expect(flat["image_mean"] as? [Double] == [0.5, 0.5, 0.5])
    #expect(flat["image_std"] as? [Double] == [0.5, 0.5, 0.5])
    #expect(flat["patch_size"] as? Int == 16)
    #expect(flat["merge_size"] as? Int == 2)
    #expect(flat["temporal_patch_size"] as? Int == 2)
    #expect(flat["do_normalize"] as? Bool == true)
    #expect(flat["image_processor_type"] as? String == "Qwen3VLImageProcessor")
    #expect(flat["processor_class"] as? String == "Qwen3VLProcessor")
    #expect(flat["image_processor"] == nil)
  }

  @Test func theLimitsBecomeTheSizeThatTheFlatLayoutUses() throws {
    let flat = try object(ProcessorConfigFix.flattened(Data(Self.nested.utf8)))
    let size = try #require(flat["size"] as? [String: Int])
    #expect(size == ["longest_edge": 16_777_216, "shortest_edge": 65_536])
    #expect(flat["max_pixels"] == nil && flat["min_pixels"] == nil)
  }

  @Test func aSizeThatIsAlreadyThereIsKept() throws {
    let json = """
      {"image_processor": {"image_mean": [0.5], "size": {"longest_edge": 100, "shortest_edge": 10}, "max_pixels": 5, "min_pixels": 1}}
      """
    let flat = try object(ProcessorConfigFix.flattened(Data(json.utf8)))
    #expect(flat["size"] as? [String: Int] == ["longest_edge": 100, "shortest_edge": 10])
  }

  @Test func withoutAProcessorClassNoneIsInvented() throws {
    let flat = try object(ProcessorConfigFix.flattened(Data(#"{"image_processor": {"image_mean": [0.5]}}"#.utf8)))
    #expect(flat["processor_class"] == nil)
  }

  @Test func aFileWithoutImageProcessorOrNotJSONGivesNothing() {
    #expect(ProcessorConfigFix.flattened(Data(#"{"image_mean": [0.5]}"#.utf8)) == nil)
    #expect(ProcessorConfigFix.flattened(Data(#"{"image_processor": 3}"#.utf8)) == nil)
    #expect(ProcessorConfigFix.flattened(Data("not json".utf8)) == nil)
  }

  @Test func theFlatFileIsAddedWhenItIsMissing() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Self.nested.write(to: folder.appendingPathComponent("processor_config.json"), atomically: true, encoding: .utf8)
    #expect(ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
    let written = try object(try Data(contentsOf: folder.appendingPathComponent("preprocessor_config.json")))
    #expect(written["image_mean"] as? [Double] == [0.5, 0.5, 0.5])
    // The original file is not touched.
    #expect(
      try String(contentsOf: folder.appendingPathComponent("processor_config.json"), encoding: .utf8) == Self.nested)
    // A second call finds the file and does nothing.
    #expect(!ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
  }

  @Test func anExistingFlatFileIsNeverReplaced() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Self.nested.write(to: folder.appendingPathComponent("processor_config.json"), atomically: true, encoding: .utf8)
    try "mine".write(to: folder.appendingPathComponent("preprocessor_config.json"), atomically: true, encoding: .utf8)
    #expect(!ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
    #expect(try String(contentsOf: folder.appendingPathComponent("preprocessor_config.json"), encoding: .utf8) == "mine")
  }

  @Test func nothingIsAddedWithoutANestedProcessorConfig() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(!ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
    try #"{"image_mean": [0.5]}"#.write(
      to: folder.appendingPathComponent("processor_config.json"), atomically: true, encoding: .utf8)
    #expect(!ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("preprocessor_config.json").path))
  }

  @Test func aFolderThatCannotBeWrittenIsNotAnError() throws {
    let folder = try makeFolder()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
      try? FileManager.default.removeItem(at: folder)
    }
    try Self.nested.write(to: folder.appendingPathComponent("processor_config.json"), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    #expect(!ProcessorConfigFix.addFlatFileIfNeeded(in: folder))
  }

  @Test func imagesOnAModelWithoutItsVisionPartGetAClearError() {
    let image = URL(fileURLWithPath: "/tmp/a.png")
    let error = MLXLanguageModelService.visionRequestError(images: [image], visionLoadError: "Key 'image_mean' not found")
    guard case .loadFailed(let detail)? = error else {
      Issue.record("expected loadFailed, got \(String(describing: error))")
      return
    }
    #expect(detail.contains("Key 'image_mean' not found"))
    #expect(detail.lowercased().contains("vision"))
  }

  @Test func withoutImagesOrWithVisionThereIsNoError() {
    let image = URL(fileURLWithPath: "/tmp/a.png")
    #expect(MLXLanguageModelService.visionRequestError(images: [], visionLoadError: "boom") == nil)
    #expect(MLXLanguageModelService.visionRequestError(images: [image], visionLoadError: nil) == nil)
  }
}
