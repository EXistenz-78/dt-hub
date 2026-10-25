import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@Suite("Sticker store")
struct PSStickerStoreTests {
  func exif(focal35: Double? = nil, x: Int? = nil, y: Int? = nil, orientation: Int? = nil) -> [CFString: Any] {
    var exif: [CFString: Any] = [:]
    if let focal35 { exif[kCGImagePropertyExifFocalLenIn35mmFilm] = Int(focal35) }
    if let x { exif[kCGImagePropertyExifPixelXDimension] = x }
    if let y { exif[kCGImagePropertyExifPixelYDimension] = y }
    var properties: [CFString: Any] = [kCGImagePropertyExifDictionary: exif]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    return properties
  }

  func size(of url: URL) -> (Int, Int) {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    return (image.width, image.height)
  }

  @Test func copiesAsPNGAndKeepsTheRelativeName() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(TestImages.solid(90, 60, 10, 20, 30), in: folder, name: "photo.jpg")
    let added = try PSStickerStore.add(contentsOf: url, into: project)
    #expect(added.file.hasPrefix("stickers/") && added.file.hasSuffix(".png"))
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(added.file).path))
    #expect(added.size == CGSize(width: 90, height: 60))
  }

  @Test func appliesTheExifOrientation() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(TestImages.solid(90, 60, 10, 20, 30), in: folder, name: "phone.jpg", properties: exif(orientation: 6))
    let added = try PSStickerStore.add(contentsOf: url, into: project)
    #expect(added.size == CGSize(width: 60, height: 90))
    #expect(size(of: project.appendingPathComponent(added.file)) == (60, 90))
  }

  @Test func keepsTheAlphaOfAPNG() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(TestImages.solid(20, 20, 255, 0, 0, 0), in: folder, name: "clear.png", type: "public.png")
    let added = try PSStickerStore.add(contentsOf: url, into: project)
    let source = CGImageSourceCreateWithURL(project.appendingPathComponent(added.file) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(TestImages.pixel(image, 10, 10).a == 0)
  }

  @Test func downscalesAHugeImage() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(TestImages.solid(4000, 3000, 10, 20, 30), in: folder, name: "huge.png", type: "public.png")
    let added = try PSStickerStore.add(contentsOf: url, into: project)
    #expect(added.size == CGSize(width: 2048, height: 1536))
  }

  @Test func emptyAndBrokenFilesThrowUnreadable() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let empty = folder.appendingPathComponent("empty.png")
    try Data().write(to: empty)
    let broken = folder.appendingPathComponent("broken.jpg")
    try Data("not a picture".utf8).write(to: broken)
    for url in [empty, broken] {
      #expect(throws: PSStickerError.unreadable(url.lastPathComponent)) { try PSStickerStore.add(contentsOf: url, into: project) }
    }
  }

  @Test func suggestedFOVComesFromTheExifFocal() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(TestImages.solid(90, 60, 1, 2, 3), in: folder, name: "a.jpg", properties: exif(focal35: 28, x: 90, y: 60))
    let fov = try #require(try PSStickerStore.add(contentsOf: url, into: project).suggestedHFOV)
    #expect(abs(fov - 65.5) < 0.1)
  }

  @Test func theOrientationIsTakenIntoAccountForTheFOV() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let url = TestImages.file(
      TestImages.solid(90, 60, 1, 2, 3), in: folder, name: "p.jpg", properties: exif(focal35: 28, x: 90, y: 60, orientation: 6))
    let fov = try #require(try PSStickerStore.add(contentsOf: url, into: project).suggestedHFOV)
    #expect(abs(fov - PSProjection.horizontalFOV(focal35mm: 28, aspect: 60.0 / 90.0)) < 0.1)
  }

  @Test func noExifOrAZeroFocalGivesNil() throws {
    let folder = TestImages.tempFolder(), project = TestImages.tempFolder()
    let plain = TestImages.file(TestImages.solid(90, 60, 1, 2, 3), in: folder, name: "plain.jpg")
    #expect(try PSStickerStore.add(contentsOf: plain, into: project).suggestedHFOV == nil)
    let zero = TestImages.file(TestImages.solid(90, 60, 1, 2, 3), in: folder, name: "zero.jpg", properties: exif(focal35: 0, x: 90, y: 60))
    #expect(try PSStickerStore.add(contentsOf: zero, into: project).suggestedHFOV == nil)
  }

  @Test func croppedDetectionComparesTheProportionsWhateverTheOrientation() {
    let size = { (w: Double, h: Double) in CGSize(width: w, height: h) }
    #expect(PSStickerStore.isCropped(recordedWidth: 90, recordedHeight: 60, size: size(60, 60)))
    #expect(!PSStickerStore.isCropped(recordedWidth: 90, recordedHeight: 60, size: size(60, 40)))
    #expect(!PSStickerStore.isCropped(recordedWidth: 90, recordedHeight: 60, size: size(40, 60)))
    #expect(!PSStickerStore.isCropped(recordedWidth: 90, recordedHeight: 60, size: size(61, 40)))
    #expect(PSStickerStore.isCropped(recordedWidth: 90, recordedHeight: 60, size: size(64, 40)))
  }
}
