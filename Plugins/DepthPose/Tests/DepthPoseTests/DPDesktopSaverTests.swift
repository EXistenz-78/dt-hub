import Foundation
import Testing

@testable import DepthPose

@Suite("DPDesktopSaver")
struct DPDesktopSaverTests {
  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dpd-desk-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func theFirstNumberIs001() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(DPDesktopSaver.nextURL(prefix: "Depth ", in: folder).lastPathComponent == "Depth 001.png")
  }

  @Test func theNumberIsOneMoreThanTheHighestOfThatPrefixOnly() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["Depth 001.png", "Depth 003.png", "Pose 007.png", "Depth notes.png", "Depth 002.jpg"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    #expect(DPDesktopSaver.nextURL(prefix: "Depth ", in: folder).lastPathComponent == "Depth 004.png")
    #expect(DPDesktopSaver.nextURL(prefix: "Pose ", in: folder).lastPathComponent == "Pose 008.png")
  }

  @Test func anEarlierFileIsNeverOverwritten() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try DPDesktopSaver.save(Data("a".utf8), prefix: "Pose ", in: folder)
    let second = try DPDesktopSaver.save(Data("b".utf8), prefix: "Pose ", in: folder)
    #expect(first.lastPathComponent == "Pose 001.png" && second.lastPathComponent == "Pose 002.png")
    #expect(try String(contentsOf: first, encoding: .utf8) == "a")
  }

  @Test func aMissingFolderThrows() {
    let gone = FileManager.default.temporaryDirectory.appendingPathComponent("dpd-gone-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try DPDesktopSaver.save(Data("a".utf8), prefix: "Depth ", in: gone) }
  }
}
