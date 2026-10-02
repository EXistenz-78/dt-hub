import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

@MainActor
struct ControlStoreMaskTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreMaskTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  func withImage(_ root: URL, width: Int = 400, height: Int = 300) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: width, height: height), name: "a.png", source: .pasteboard)
    return store
  }

  func spot(_ store: ControlStore, at point: CGPoint = CGPoint(x: 50, y: 50), radius: Double = 10) -> MaskBitmap {
    let size = store.maskSize!
    var bitmap = store.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: radius, erase: false)
    return bitmap
  }

  @Test func theMaskIsDrawnAtTheWorkingSizeOfTheImage() throws {
    let store = try withImage(folder(), width: 4000, height: 2000)
    let size = try #require(store.maskSize)
    #expect(size.width == 1024 && size.height == 512)
  }

  @Test func aCommittedMaskIsKeptAndComesBackFromDisk() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    let reference = try #require(store.inputs.mask)
    #expect(reference.coverage > 0)
    let back = try #require(store.maskBitmap())
    #expect(back.width == 400 && back.height == 300)
    #expect(back.pixels[50 * back.width + 50] >= 128)
    #expect(copies(in: root).contains(reference.fileName))
  }

  @Test func eachStrokeIsAStepOfTheHistory() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    let first = store.inputs.mask
    try store.commitMask(spot(store, at: CGPoint(x: 300, y: 200)))
    #expect(store.inputs.mask != first)
    store.undo()
    #expect(store.inputs.mask == first)
    let back = try #require(store.maskBitmap())
    #expect(back.pixels[200 * back.width + 300] < 128)
    store.undo()
    #expect(store.inputs.mask == nil)
    store.redo()
    store.redo()
    #expect(store.inputs.mask != first)
  }

  @Test func anEmptyMaskIsNoMask() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    var bitmap = try #require(store.maskBitmap())
    bitmap.clear()
    try store.commitMask(bitmap)
    #expect(store.inputs.mask == nil)
  }

  @Test func committingAnEmptyMaskWithoutOneChangesNothing() throws {
    let store = try withImage(folder())
    let size = try #require(store.maskSize)
    try store.commitMask(MaskBitmap(width: size.width, height: size.height))
    #expect(store.inputs.mask == nil)
    #expect(store.canUndo)  // only the image's step
    store.undo()
    #expect(store.inputs.image == nil)
  }

  @Test func invertingAMaskDrawnNothingPaintsEverything() throws {
    let store = try withImage(folder())
    try store.invertMask()
    #expect(try #require(store.inputs.mask).coverage == 1)
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func clearingTheMaskSaysSoAndCanBeUndone() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    let reference = store.inputs.mask
    store.clearMask()
    #expect(store.inputs.mask == nil)
    #expect(store.notice == nil)  // no message: the arrows undo it, and a message moves the cards
    store.undo()
    #expect(store.inputs.mask == reference)
  }

  @Test func theMaskGoesWithTheImage() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.mask == nil)
    store.undo()
    #expect(store.inputs.mask != nil)
    store.removeImage()
    #expect(store.inputs.mask == nil)
  }

  @Test func withoutAnImageThereIsNothingToDraw() throws {
    let store = store(in: folder())
    #expect(store.maskSize == nil)
    try store.commitMask(MaskBitmap(width: 10, height: 10))
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func theMaskSurvivesARestart() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      store.setMaskSettings(MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    }
    let again = store(in: root)
    #expect(again.inputs.mask != nil)
    #expect(again.inputs.maskSettings == MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    #expect(again.maskBitmap() != nil)
  }

  @Test func aMaskWhoseCopyIsGoneIsDroppedWithANotice() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      let name = try #require(store.inputs.mask?.fileName)
      try FileManager.default.removeItem(at: root.appendingPathComponent("Control").appendingPathComponent(name))
    }
    let again = store(in: root)
    #expect(again.inputs.mask == nil)
    #expect(again.inputs.image != nil)
    #expect(again.notice == .maskMissingAtLaunch)
  }

  @Test func theCopiesOfOldMasksAreSweptWhenNothingRefersToThem() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    try store.commitMask(spot(store, at: CGPoint(x: 100, y: 100)))
    let image = try #require(store.inputs.image).fileName
    #expect(copies(in: root).count == 3)  // image + the two masks (the first one is in the history)
    store.clear()
    store.undo()
    #expect(copies(in: root).count == 3)
    #expect(copies(in: root).contains(image))
  }

  @Test func undoAndRedoLeaveTheSettingsAndTheCutAsTheUserSetThem() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    store.setMaskSettings(MaskSettings(blur: 8, outset: 20, preserveOriginal: false))
    store.setStrength(0.4)
    store.setOffset(x: 1, y: 0)
    store.undo()  // takes the stroke away; the snapshot it brings back has the settings of before
    #expect(store.inputs.mask == nil)
    #expect(store.inputs.maskSettings == MaskSettings(blur: 8, outset: 20, preserveOriginal: false))
    #expect(store.inputs.strength == 0.4)
    #expect(store.inputs.framing.offsetX == 1)
    store.redo()
    #expect(store.inputs.maskSettings == MaskSettings(blur: 8, outset: 20, preserveOriginal: false))
    #expect(store.inputs.strength == 0.4)
    #expect(store.inputs.framing.offsetX == 1)
  }

  @Test func theMaskSettingsAreClamped() throws {
    let store = try withImage(folder())
    store.setMaskSettings(MaskSettings(blur: 500, outset: -4, preserveOriginal: true))
    #expect(store.inputs.maskSettings.blur == MaskSettings.blurRange.upperBound)
    #expect(store.inputs.maskSettings.outset == 0)
  }

  @Test func withAMaskTheAutomaticStrengthIsFull() throws {
    let store = try withImage(folder())
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.7)
    try store.commitMask(spot(store))
    #expect(store.inputs.effectiveStrength(editModel: false) == 1.0)
    store.setStrength(0.4)
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.4)
  }

  @Test func aRunGetsTheMaskAtTheCanvasSizeNextToTheImage() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    try store.commitMask(spot(store, at: CGPoint(x: 20, y: 20), radius: 15))
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    let mask = try #require(inputs.mask)
    #expect(mask.width == 256 && mask.height == 192)
    #expect(inputs.image?.width == 256)
    #expect(inputs.isEmpty == false)
  }

  @Test func withoutAMaskARunHasNone() async throws {
    let store = try withImage(folder())
    let pending = store.pendingInputs(canvasWidth: 128, canvasHeight: 96)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.mask == nil)
  }

  // MARK: The Brush drawing

  func drawing(_ store: ControlStore, at point: CGPoint = CGPoint(x: 50, y: 50)) -> PaintBitmap {
    let size = store.maskSize!
    var bitmap = store.paintBitmap() ?? PaintBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: 10, red: 200, green: 20, blue: 20)
    return bitmap
  }

  @Test func aCommittedDrawingIsKeptAndComesBackFromDisk() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitPaint(drawing(store))
    let reference = try #require(store.inputs.paint)
    let back = try #require(store.paintBitmap())
    #expect(back.width == 400 && back.height == 300)
    #expect(back.alpha(x: 50, y: 50) == 255)
    #expect(copies(in: root).contains(reference.fileName))
  }

  @Test func eachDrawingStrokeIsAStepOfTheHistory() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store, at: CGPoint(x: 50, y: 50)))
    let first = store.inputs.paint
    try store.commitPaint(drawing(store, at: CGPoint(x: 300, y: 200)))
    store.undo()
    #expect(store.inputs.paint == first)
    store.undo()
    #expect(store.inputs.paint == nil)
    store.redo()
    #expect(store.inputs.paint == first)
  }

  @Test func anEmptyDrawingIsNoDrawing() throws {
    let store = try withImage(folder())
    let size = try #require(store.maskSize)
    try store.commitPaint(PaintBitmap(width: size.width, height: size.height))
    #expect(store.inputs.paint == nil)
    try store.commitPaint(drawing(store))
    try store.commitPaint(PaintBitmap(width: size.width, height: size.height))
    #expect(store.inputs.paint == nil)
  }

  @Test func clearingTheDrawingSaysSoAndCanBeUndone() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    let reference = store.inputs.paint
    store.clearPaint()
    #expect(store.inputs.paint == nil)
    #expect(store.notice == nil)
    store.undo()
    #expect(store.inputs.paint == reference)
  }

  @Test func theDrawingAndTheMaskAreIndependent() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    try store.commitMask(spot(store))
    store.clearMask()
    #expect(store.inputs.paint != nil)
    store.clearPaint()
    #expect(store.inputs.mask == nil)
  }

  @Test func theDrawingGoesWithTheImage() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.paint == nil)
    store.undo()
    #expect(store.inputs.paint != nil)
    store.removeImage()
    #expect(store.inputs.paint == nil)
  }

  @Test func theDrawingSurvivesARestartAndALostCopyIsDropped() throws {
    let root = folder()
    var name = ""
    do {
      let store = try withImage(root)
      try store.commitPaint(drawing(store))
      name = try #require(store.inputs.paint?.fileName)
    }
    #expect(store(in: root).inputs.paint?.fileName == name)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control").appendingPathComponent(name))
    let again = store(in: root)
    #expect(again.inputs.paint == nil)
    #expect(again.inputs.image != nil)
    #expect(again.notice == .paintMissingAtLaunch)
  }

  @Test func aRunGetsTheImageWithTheDrawingOnIt() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    try store.commitPaint(drawing(store, at: CGPoint(x: 200, y: 150)))
    let pending = store.pendingInputs(canvasWidth: 400, canvasHeight: 300)
    let inputs = try await Task.detached { try pending.render() }.value
    let image = try #require(inputs.image)
    // The picture is solid (0.2, 0.6, 0.9); the middle of it carries the red mark.
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -200, y: -(300 - 1 - 150), width: 400, height: 300))
    #expect(bytes[0] > 150 && bytes[2] < 80)
  }
}
