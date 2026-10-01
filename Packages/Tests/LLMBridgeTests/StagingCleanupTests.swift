import Foundation
import Testing

@testable import LLMBridge

struct StagingCleanupTests {
  /// A download that was cut short by quitting leaves its hidden staging folder: it is removed,
  /// and nothing else is.
  @Test func removesOnlyTheLeftoverStagingFolders() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("StagingCleanupTests-\(UUID())")
    let fileManager = FileManager.default
    for name in [".dthub-download-AAA", ".dthub-download-BBB", "a-model", ".hidden-other"] {
      try fileManager.createDirectory(at: parent.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try Data(count: 10).write(to: parent.appendingPathComponent(".dthub-download-AAA/part.safetensors"))
    HubLanguageModelDownloader.removeLeftoverStaging(in: parent)
    let left = try fileManager.contentsOfDirectory(atPath: parent.path).sorted()
    #expect(left == [".hidden-other", "a-model"])
    try? fileManager.removeItem(at: parent)
  }

  @Test func aMissingFolderIsNotAnError() {
    HubLanguageModelDownloader.removeLeftoverStaging(
      in: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID())"))
  }
}
