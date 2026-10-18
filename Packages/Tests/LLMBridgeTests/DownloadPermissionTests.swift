import Foundation
import HubKit
import Testing

@testable import LLMBridge

struct DownloadPermissionTests {
  /// A destination whose parent cannot be written fails at once, before any network request, with the
  /// folder named (not the system's raw text).
  @Test func anUnwritableFolderGivesFolderNotWritable() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("DownloadPermissionTests-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
    defer {
      try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
      try? fileManager.removeItem(at: root)
    }
    let destination = root.appendingPathComponent("models/model", isDirectory: true)
    do {
      try await HubLanguageModelDownloader().download(
        repository: "mlx-community/some-model", to: destination, progress: { _ in })
      Issue.record("expected an error")
    } catch let error as LanguageModelError {
      guard case .folderNotWritable(let path) = error else {
        Issue.record("wrong error \(error)")
        return
      }
      #expect(path.hasPrefix(root.path))
    }
  }

  @Test func plainTextNamesTheFolder() {
    let text = LanguageModelError.folderNotWritable("/x/y").plainText
    #expect(text.contains("/x/y"))
  }
}
