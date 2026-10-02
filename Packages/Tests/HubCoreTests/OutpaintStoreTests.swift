import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct OutpaintStoreTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("OutpaintStoreTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func withImage(_ root: URL, width: Int = 400, height: Int = 300) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: width, height: height), name: "a.png", source: .pasteboard)
    return store
  }

  @Test func theZoomIsLimitedAndKeptAcrossARestart() throws {
    let root = folder()
    let first = try withImage(root)
    first.setZoom(-300)
    #expect(first.inputs.framing.zoom == -100)
    first.setZoom(-40)
    first.setOffset(x: 0.5, y: 0)
    #expect(first.inputs.framing == Framing(zoom: -40, offsetX: 0.5))
    let second = store(in: root)
    #expect(second.inputs.framing == Framing(zoom: -40, offsetX: 0.5))
  }

  @Test func theZoomIsNotAStepOfTheHistory() throws {
    let store = try withImage(folder())
    store.setZoom(-40)
    var mask = MaskBitmap(width: store.maskSize!.width, height: store.maskSize!.height)
    mask.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20), radius: 5, erase: false)
    try store.commitMask(mask)
    store.undo()
    #expect(store.inputs.framing.zoom == -40)
    store.redo()
    #expect(store.inputs.framing.zoom == -40)
  }

  @Test func aNewImageStartsAtTheFillAndResetPutsItBack() throws {
    let store = try withImage(folder())
    store.setZoom(-40)
    store.setOffset(x: 1, y: 1)
    store.resetFraming()
    #expect(store.inputs.framing == Framing())
    store.setZoom(60)
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.framing == Framing())
  }

  @Test func marginsExistOnlyWhenTheImageIsSmallerThanTheCanvas() throws {
    let store = try withImage(folder(), width: 400, height: 300)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
    store.setZoom(-50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300))
    store.setZoom(50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
    store.removeImage()
    store.setZoom(-50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
  }

  @Test func theStrongCropWarningIsOnlyForAZoomOfZeroOrLess() throws {
    let store = try withImage(folder(), width: 300, height: 400)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900) == [.strongCrop(percent: 44)])
    store.setZoom(-100)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)
    store.setZoom(50)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)
  }

  @Test func aRunWithMarginsGetsTheMaskAndTheGreyImageAtTheCanvasSize() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    store.setZoom(-50)
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    let image = try #require(inputs.image)
    let mask = try #require(inputs.mask)
    #expect(image.width == 256 && image.height == 192)
    #expect(mask.width == 256 && mask.height == 192)
    #expect(inputs.isEmpty == false)
  }

  @Test func aRunAtTheFillWithoutAMaskHasNoMask() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.mask == nil)
  }

  @Test func theBiggestZoomOfAHugeImageStillRenders() async throws {
    let store = try withImage(folder(), width: 4000, height: 3000)
    store.setZoom(100)
    let pending = store.pendingInputs(canvasWidth: 512, canvasHeight: 384)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.image?.width == 512 && inputs.mask == nil)
  }
}
