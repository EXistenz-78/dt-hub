import Foundation
import Testing

@testable import HubCore

struct FolderAccessTests {
  private func temp() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("FolderAccess-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func anExistingFolderIsReadable() throws {
    let dir = try temp()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(FolderAccess.access(of: dir.path) == .readable)
  }

  @Test func aMissingPathIsMissing() {
    #expect(FolderAccess.access(of: "/tmp/FolderAccess-\(UUID())/nope") == .missing)
  }

  @Test func aFolderWithoutPermissionIsDenied() throws {
    let dir = try temp()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
      try? FileManager.default.removeItem(at: dir)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
    #expect(FolderAccess.access(of: dir.path) == .denied)
  }

  @Test func aFileInsteadOfAFolderIsReadable() throws {
    let dir = try temp()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.txt")
    try Data().write(to: file)
    #expect(FolderAccess.access(of: file.path) == .readable)
  }
}
