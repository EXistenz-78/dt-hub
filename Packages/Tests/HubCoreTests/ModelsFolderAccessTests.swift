import Foundation
import Testing

@testable import HubCore

struct ModelsFolderAccessTests {
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func aFolderWithReadableFilesIsReadable() throws {
    let dir = try folder()
    try Data("[]".utf8).write(to: dir.appendingPathComponent("custom_lora.json"))
    #expect(FolderAccess.accessIncludingModelFiles(of: dir.path) == .readable)
  }

  @Test func missingJSONFilesAreNoProblem() throws {
    #expect(FolderAccess.accessIncludingModelFiles(of: try folder().path) == .readable)
  }

  @Test func aMissingFolderIsMissing() {
    #expect(FolderAccess.accessIncludingModelFiles(of: "/nonexistent-\(UUID().uuidString)") == .missing)
  }

  @Test func aRefusedFileMakesTheFolderDenied() throws {
    let dir = try folder()
    let file = dir.appendingPathComponent("custom_lora.json")
    try Data("[]".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
    #expect(FolderAccess.accessIncludingModelFiles(of: dir.path) == .denied)
  }
}
