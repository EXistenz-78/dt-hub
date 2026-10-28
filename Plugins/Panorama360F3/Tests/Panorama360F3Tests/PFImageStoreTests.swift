import Foundation
import Testing

@testable import Panorama360F3

struct PFImageStoreTests {
  @Test func addWritesAPNGInTheImagesFolder() throws {
    let project = TestImages.tempFolder()
    let source = TestImages.png(width: 100, height: 50, in: TestImages.tempFolder(), name: "lake.png")
    let added = try PFImageStore.add(contentsOf: source, into: project)
    #expect(added.file.hasPrefix("images/") && added.file.hasSuffix(".png"))
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(added.file).path))
    #expect(added.name == "lake.png")
    #expect(added.visible)
  }

  @Test func aLongPictureIsReducedTo2048() throws {
    let project = TestImages.tempFolder()
    let source = TestImages.png(width: 3000, height: 1000, in: TestImages.tempFolder())
    let added = try PFImageStore.add(contentsOf: source, into: project)
    let size = try #require(TestImages.size(of: project.appendingPathComponent(added.file)))
    #expect(size.width == 2048)
    #expect(abs(size.height - 683) <= 1)
  }

  @Test func anUnreadableFileThrowsUnreadable() throws {
    let folder = TestImages.tempFolder()
    let text = folder.appendingPathComponent("notes.txt")
    try Data("not a picture".utf8).write(to: text)
    #expect(throws: PFImageError.unreadable("notes.txt")) {
      try PFImageStore.add(contentsOf: text, into: TestImages.tempFolder())
    }
  }
}
