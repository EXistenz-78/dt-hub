import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// Local editing in `ControlStore`: a crop of the start image is retouched, then put back or dropped.
@MainActor
struct ControlStoreLocalEditTests {
  /// 2048×1024: the mask and the drawing are kept at half size (1024×512).
  static let (width, height) = (2048, 1024)
  /// A 512×512 crop; in the mask and the drawing it is (256, 128, 256, 256).
  static let rect = PixelRect(x: 512, y: 256, width: 512, height: 512)
  /// The centre of the crop, in mask pixels.
  static let spot = CGPoint(x: 384, y: 256)

  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreLocalEditTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  func withImage(_ root: URL) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: Self.width, height: Self.height), name: "photo.png", source: .pasteboard)
    return store
  }

  func addMask(_ store: ControlStore, at point: CGPoint = spot) throws {
    let size = try #require(store.maskSize)
    var bitmap = store.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: 20, erase: false)
    try store.commitMask(bitmap)
  }

  func addPaint(_ store: ControlStore) throws {
    let size = try #require(store.maskSize)
    var bitmap = PaintBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: Self.spot, to: Self.spot, radius: 20, red: 255, green: 0, blue: 0)
    try store.commitPaint(bitmap)
  }

  func begin(_ store: ControlStore) throws {
    try store.beginLocalEdit(rect: Self.rect, generation: (width: 1024, height: 768, highRes: false))
  }

  @Test func beginningMakesTheCropTheStartImage() throws {
    let store = try withImage(folder())
    store.setZoom(30)
    store.setStrength(0.6)
    let original = try #require(store.inputs.image)
    try begin(store)
    let image = try #require(store.inputs.image)
    #expect(image.pixelWidth == 512 && image.pixelHeight == 512)
    #expect(image.name == "photo (crop).png")
    #expect(image.source == .plugin(id: "localEdit"))
    let session = try #require(store.inputs.localEdit)
    #expect(session.original == original)
    #expect(session.rect == Self.rect)
    #expect(session.framing.zoom == 30)
    #expect(session.strength == 0.6)
    #expect(session.generationWidth == 1024 && session.generationHeight == 768 && !session.generationHighRes)
    #expect(store.inputs.framing == Framing())
    #expect(store.inputs.strength == 0.6)
    #expect(store.preview(maxPixel: 2048)?.width == 512)
    #expect(store.originalImage(maxPixel: nil)?.width == Self.width)
    #expect(store.originalImage(maxPixel: 256)?.width == 256)
  }

  @Test func beginningTwiceIsRefused() throws {
    let store = try withImage(folder())
    try begin(store)
    #expect(throws: ControlError.localEditOpen) { try begin(store) }
  }

  @Test func theMaskAndTheDrawingAreCroppedToo() throws {
    let store = try withImage(folder())
    try addMask(store)
    try addPaint(store)
    let (mask, paint) = (try #require(store.inputs.mask), try #require(store.inputs.paint))
    try begin(store)
    let croppedMask = try #require(store.inputs.mask)
    let croppedPaint = try #require(store.inputs.paint)
    #expect(croppedMask.fileName != mask.fileName)
    #expect(croppedPaint.fileName != paint.fileName)
    #expect(croppedMask.coverage > mask.coverage)
    #expect(store.inputs.localEdit?.mask == mask)
    #expect(store.inputs.localEdit?.paint == paint)
    // At the crop's working size, the spot in the middle and nothing in the corner.
    let maskBitmap = try #require(store.maskBitmap())
    #expect(maskBitmap.width == 512 && maskBitmap.height == 512)
    #expect(maskBitmap.pixels[256 * 512 + 256] >= 128)
    #expect(maskBitmap.pixels[10 * 512 + 10] < 128)
    let paintBitmap = try #require(store.paintBitmap())
    #expect(paintBitmap.width == 512 && paintBitmap.height == 512)
    #expect(paintBitmap.alpha(x: 256, y: 256) == 255)
    #expect(paintBitmap.color(x: 256, y: 256).red == 255)
    #expect(paintBitmap.alpha(x: 10, y: 10) == 0)
  }

  @Test func anEmptyCropOfTheMaskIsNoMask() throws {
    let store = try withImage(folder())
    try addMask(store, at: CGPoint(x: 50, y: 50))
    try begin(store)
    #expect(store.inputs.mask == nil)
    #expect(store.inputs.localEdit?.mask != nil)
  }

  @Test func undoAfterBeginningBringsEverythingBack() throws {
    let store = try withImage(folder())
    try addMask(store)
    let before = store.inputs
    try begin(store)
    store.undo()
    #expect(store.inputs == before)
    #expect(store.inputs.localEdit == nil)
    #expect(store.maskBitmap()?.width == 1024)
    store.redo()
    #expect(store.inputs.localEdit != nil)
    #expect(store.inputs.image?.pixelWidth == 512)
  }

  @Test func cancelBringsBackTheOriginalAndTheMask() throws {
    let store = try withImage(folder())
    try addMask(store)
    store.setZoom(-20)
    let before = store.inputs
    try begin(store)
    try addMask(store, at: CGPoint(x: 100, y: 100))
    store.cancelLocalEdit()
    #expect(store.inputs.image == before.image)
    #expect(store.inputs.mask == before.mask)
    #expect(store.inputs.framing == before.framing)
    #expect(store.inputs.localEdit == nil)
    store.undo()
    #expect(store.inputs.localEdit != nil)
  }

  @Test func confirmPutsTheMontageAndClosesTheSession() throws {
    let store = try withImage(folder())
    try addMask(store)
    try addPaint(store)
    store.setZoom(10)
    let before = store.inputs
    try begin(store)
    store.setZoom(50)
    try store.confirmLocalEdit(montage: pictureData(width: Self.width, height: Self.height), name: "montage.png")
    let image = try #require(store.inputs.image)
    #expect(image.source == .result)
    #expect(image.name == "montage.png")
    #expect(image.id != before.image?.id)
    #expect(image.pixelWidth == Self.width)
    #expect(store.inputs.framing == before.framing)
    #expect(store.inputs.mask == before.mask)
    #expect(store.inputs.paint == before.paint)
    #expect(store.inputs.localEdit == nil)
  }

  @Test func confirmingWithoutASessionDoesNothing() throws {
    let store = try withImage(folder())
    let before = store.inputs
    let couldUndo = store.canUndo
    try store.confirmLocalEdit(montage: pictureData(width: 64, height: 64), name: "montage.png")
    store.cancelLocalEdit()
    #expect(store.inputs == before)
    #expect(store.canUndo == couldUndo)
  }

  @Test func undoAfterConfirmReopensTheSession() throws {
    let store = try withImage(folder())
    try begin(store)
    let session = try #require(store.inputs.localEdit)
    let crop = store.inputs.image
    try store.confirmLocalEdit(montage: pictureData(width: Self.width, height: Self.height), name: "montage.png")
    store.undo()
    #expect(store.inputs.localEdit == session)
    #expect(store.inputs.image == crop)
    store.redo()
    #expect(store.inputs.localEdit == nil)
    #expect(store.inputs.image?.name == "montage.png")
  }

  @Test func theStartImageCannotBeReplacedDuringASession() throws {
    let store = try withImage(folder())
    try begin(store)
    let during = store.inputs
    #expect(throws: ControlError.localEditOpen) {
      try store.setImage(data: pictureData(width: 64, height: 64), name: "other.png", source: .pasteboard)
    }
    #expect(store.inputs == during)
    store.removeImage()
    #expect(store.notice == .localEditOpen)
    #expect(store.inputs == during)
    store.dismissNotice()
    store.clear()
    #expect(store.notice == .localEditOpen)
    #expect(store.inputs == during)
  }

  @Test func theOriginalFileSurvivesTheGarbageCollection() throws {
    let root = folder()
    let store = try withImage(root)
    try addMask(store)
    let original = try #require(store.inputs.image)
    let mask = try #require(store.inputs.mask)
    try begin(store)
    // More steps than the history keeps: the state before the session is gone from it.
    for index in 0..<25 { try addMask(store, at: CGPoint(x: 260 + index * 5, y: 140)) }
    #expect(copies(in: root).contains(original.fileName))
    #expect(copies(in: root).contains(mask.fileName))
    store.cancelLocalEdit()
    #expect(store.inputs.image == original)
    #expect(store.inputs.mask == mask)
  }

  @Test func theSessionSurvivesAReload() throws {
    let root = folder()
    let store = try withImage(root)
    try begin(store)
    store.setLocalEditMatchColors(false)
    let reloaded = self.store(in: root)
    #expect(reloaded.inputs.localEdit == store.inputs.localEdit)
    #expect(reloaded.inputs.localEdit?.matchColors == false)
    #expect(reloaded.inputs.image == store.inputs.image)
    #expect(reloaded.originalImage(maxPixel: nil)?.width == Self.width)
  }

  @Test func matchColorsIsOutsideTheHistory() throws {
    let store = try withImage(folder())
    try begin(store)
    #expect(store.inputs.localEdit?.matchColors == true)
    let couldUndo = store.canUndo
    store.setLocalEditMatchColors(false)
    #expect(store.inputs.localEdit?.matchColors == false)
    #expect(store.canUndo == couldUndo)
    try addMask(store, at: CGPoint(x: 100, y: 100))
    store.undo()
    #expect(store.inputs.localEdit?.matchColors == false)
    store.redo()
    #expect(store.inputs.localEdit?.matchColors == false)
  }

  @Test func theChangeIsReportedForEveryWay() throws {
    let (a, b) = (folder(), folder())
    let store = try withImage(a)
    var changes: [(old: UUID?, new: UUID?)] = []
    store.onLocalEditChange = { old, new in changes.append((old?.id, new?.id)) }

    try begin(store)
    let id = try #require(store.inputs.localEdit?.id)
    #expect(changes.count == 1 && changes.last?.old == nil && changes.last?.new == id)
    store.setLocalEditMatchColors(false)
    try addMask(store, at: CGPoint(x: 100, y: 100))
    #expect(changes.count == 1)
    store.undo()  // the stroke: same session
    #expect(changes.count == 1)
    store.undo()  // the beginning
    #expect(changes.count == 2 && changes.last?.old == id && changes.last?.new == nil)
    store.redo()
    #expect(changes.count == 3 && changes.last?.new == id)
    store.cancelLocalEdit()
    #expect(changes.count == 4 && changes.last?.old == id && changes.last?.new == nil)
    store.undo()
    #expect(changes.count == 5 && changes.last?.new == id)
    try store.confirmLocalEdit(montage: pictureData(width: Self.width, height: Self.height), name: "montage.png")
    #expect(changes.count == 6 && changes.last?.old == id && changes.last?.new == nil)
    store.undo()
    #expect(changes.count == 7 && changes.last?.new == id)
    store.switchTo(storage: FileReferenceStorage(folder: b.appendingPathComponent("Control")), fileURL: b.appendingPathComponent("control.json"))
    #expect(changes.count == 8 && changes.last?.old == id && changes.last?.new == nil)
    store.switchTo(storage: FileReferenceStorage(folder: a.appendingPathComponent("Control")), fileURL: a.appendingPathComponent("control.json"))
    #expect(changes.count == 9 && changes.last?.old == nil && changes.last?.new == id)
  }
}
