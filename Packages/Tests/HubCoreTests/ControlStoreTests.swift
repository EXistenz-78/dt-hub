import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

/// PNG (or JPEG) bytes of a solid picture; `orientation` is the EXIF orientation to write.
func pictureData(width: Int, height: Int, type: UTType = .png, orientation: Int? = nil) -> Data {
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
  var properties: [CFString: Any] = [:]
  if let orientation { properties[kCGImagePropertyOrientation] = orientation }
  CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
  CGImageDestinationFinalize(destination)
  return data as Data
}

@MainActor
struct ControlStoreTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL, undoLimit: Int = 20) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"), undoLimit: undoLimit)
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  @Test func anImageIsCopiedAndDescribed() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 300, height: 200), name: "cat.png", source: .file(path: "/x/cat.png"))
    let image = try #require(store.inputs.image)
    #expect(image.pixelWidth == 300 && image.pixelHeight == 200)
    #expect(image.name == "cat.png")
    #expect(image.source == .file(path: "/x/cat.png"))
    #expect(copies(in: root) == [image.fileName])
    #expect(image.fileName.hasSuffix(".png"))
  }

  @Test func theStartImageHasAFileAndNothingElseDoes() throws {
    let root = folder()
    let store = store(in: root)
    #expect(store.startImageURL == nil)
    try store.setImage(data: pictureData(width: 30, height: 20), name: "cat.png", source: .pasteboard)
    let url = try #require(store.startImageURL)
    #expect(url.deletingLastPathComponent().lastPathComponent == "Control")
    #expect(FileManager.default.fileExists(atPath: url.path))
    store.removeImage()
    #expect(store.startImageURL == nil)
  }

  @Test func theMoodboardFilesAreThoseThatAreOnInTheOrderOfTheThumbnails() throws {
    let store = store(in: folder())
    #expect(store.moodboardURLs.isEmpty)
    try addPictures(store, 3)
    let all = store.moodboardURLs
    #expect(all.count == 3 && all.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    store.setMoodboardOn(id: store.inputs.moodboard[1].id, isOn: false)
    #expect(store.moodboardURLs == [all[0], all[2]])
  }

  @Test func theSizeFollowsTheExifOrientation() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 300, height: 200, type: .jpeg, orientation: 6), name: "p.jpg", source: .pasteboard)
    #expect(store.inputs.image?.pixelWidth == 200)
    #expect(store.inputs.image?.pixelHeight == 300)
  }

  @Test func anUnreadableFileIsRefusedAndLeavesNothing() throws {
    let root = folder()
    let store = store(in: root)
    #expect(throws: ControlError.unreadable("notes.txt")) {
      try store.setImage(data: Data("not an image".utf8), name: "notes.txt", source: .pasteboard)
    }
    #expect(store.inputs.image == nil)
    #expect(copies(in: root).isEmpty)
  }

  @Test func removingAnImageCanBeUndoneAndRedone() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    let image = try #require(store.inputs.image)
    store.removeImage()
    #expect(store.inputs.image == nil)
    #expect(store.notice == .removed(name: "a.png"))
    #expect(store.canUndo)
    store.undo()
    #expect(store.inputs.image == image)
    #expect(store.canRedo)
    store.redo()
    #expect(store.inputs.image == nil)
  }

  @Test func replacingKeepsTheOldCopyWhileItCanBeUndoneAndDropsItAfterwards() throws {
    let root = folder()
    let store = store(in: root, undoLimit: 2)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "one.png", source: .pasteboard)
    let first = try #require(store.inputs.image)
    try store.setImage(data: pictureData(width: 32, height: 32), name: "two.png", source: .pasteboard)
    #expect(store.notice == .replaced(name: "one.png"))
    #expect(copies(in: root).count == 2)
    store.undo()
    #expect(store.inputs.image == first)
    store.redo()
    // Two more changes push the first state out of the history: its copy goes away.
    try store.setImage(data: pictureData(width: 16, height: 16), name: "three.png", source: .pasteboard)
    try store.setImage(data: pictureData(width: 8, height: 8), name: "four.png", source: .pasteboard)
    #expect(!copies(in: root).contains(first.fileName))
  }

  @Test func clearingRemovesEverythingTheTabHolds() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    store.setStrength(0.3)
    store.setOffset(x: 0.5, y: -0.5)
    store.clear()
    #expect(store.inputs == ControlInputs())
    #expect(store.notice == .cleared)
    store.undo()
    #expect(store.inputs.image?.name == "a.png")
    #expect(store.inputs.strength == 0.3)
  }

  @Test func strengthAndOffsetAreClampedAndNewImagesStartCentered() throws {
    let store = store(in: folder())
    store.setStrength(7)
    #expect(store.inputs.strength == 1)
    store.setStrength(nil)
    #expect(store.inputs.strength == nil)
    store.setOffset(x: 9, y: -9)
    #expect(store.inputs.framing == Framing(offsetX: 1, offsetY: -1))
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    #expect(store.inputs.framing == Framing())
  }

  @Test func everythingComesBackAtTheNextLaunch() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "a.png", source: .result)
    first.setStrength(0.4)
    first.setOffset(x: 0.25, y: 0)
    let second = store(in: root)
    #expect(second.inputs == first.inputs)
    #expect(second.notice == nil)
    #expect(!second.canUndo)
  }

  @Test func aMissingCopyIsDroppedWithANotice() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "gone.png", source: .pasteboard)
    first.setStrength(0.4)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control/\(try #require(first.inputs.image).fileName)"))
    let second = store(in: root)
    #expect(second.inputs.image == nil)
    #expect(second.notice == .missingAtLaunch(name: "gone.png"))
    #expect(second.inputs.strength == 0.4)
  }

  @Test func strayFilesAreSweptAtLaunch() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "a.png", source: .pasteboard)
    let kept = try #require(first.inputs.image).fileName
    try Data(count: 10).write(to: root.appendingPathComponent("Control/orphan.png"))
    _ = store(in: root)
    #expect(copies(in: root) == [kept])
  }

  @Test func aStrongCropIsReported() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 750, height: 1000), name: "tall.png", source: .pasteboard)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900) == [.strongCrop(percent: 44)])
    try store.setImage(data: pictureData(width: 1000, height: 1000), name: "square.png", source: .pasteboard)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)  // 25 %: below a third
    #expect(store.warnings(canvasWidth: 1000, canvasHeight: 1000).isEmpty)
  }

  @Test func anImageInMemoryBecomesAPNGCopy() throws {
    let root = folder()
    let store = store(in: root)
    let source = try #require(CGImageSourceCreateWithData(pictureData(width: 40, height: 30) as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    try store.setImage(image, name: "result.png", source: .result)
    #expect(store.inputs.image?.pixelWidth == 40)
    #expect(copies(in: root).count == 1)
  }

  @Test func aFileFromResultsKeepsItsSourceAndAnUnreadableOneIsReported() async throws {
    let root = folder()
    let store = store(in: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("made.png")
    try pictureData(width: 50, height: 40).write(to: file)
    try await store.setImage(fileURL: file, source: .result)
    #expect(store.inputs.image?.source == .result)
    try await store.setImage(fileURL: file)
    #expect(store.inputs.image?.source == .file(path: file.path))
    await #expect(throws: ControlError.unreadable("missing.png")) {
      try await store.setImage(fileURL: root.appendingPathComponent("missing.png"))
    }
  }

  @Test func thePreviewIsDecodedSmallAndOnlyForAnExistingImage() throws {
    let store = store(in: folder())
    #expect(store.preview(maxPixel: 100) == nil)
    try store.setImage(data: pictureData(width: 800, height: 400), name: "a.png", source: .pasteboard)
    let preview = try #require(store.preview(maxPixel: 100))
    #expect(preview.width == 100 && preview.height == 50)
  }

  @Test func theRunGetsTheImageFramedToTheCanvas() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 600, height: 400), name: "a.png", source: .pasteboard)
    let framed = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().image)
    #expect(framed.width == 256 && framed.height == 256)
    let empty = ControlStore(storage: FileReferenceStorage(folder: folder()), fileURL: folder().appendingPathComponent("c.json"))
    #expect(try empty.pendingInputs(canvasWidth: 64, canvasHeight: 64).render().isEmpty)
  }

  @Test func undoAndRedoAvailabilityCanBeObserved() throws {
    let store = store(in: folder())
    let changes = Counter()
    func watch(_ read: @escaping @Sendable () -> Bool) {
      withObservationTracking { _ = read() } onChange: { changes.add() }
    }
    watch { MainActor.assumeIsolated { store.canUndo } }
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    #expect(changes.count == 1)
    store.removeImage()
    watch { MainActor.assumeIsolated { store.canRedo } }
    store.undo()
    #expect(changes.count == 2)
    watch { MainActor.assumeIsolated { store.canUndo } }
    store.redo()
    #expect(changes.count == 3)
  }

  @Test func aTruncatedPictureIsRefusedAtImport() throws {
    let root = folder()
    let store = store(in: root)
    // Noise does not compress: cutting the file falls in the middle of the picture data.
    var noise = [UInt8](repeating: 0, count: 300 * 300 * 4)
    for index in noise.indices { noise[index] = UInt8.random(in: 0...255) }
    let context = CGContext(
      data: &noise, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 1200,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    let cut = (data as Data).prefix(data.length / 2)
    #expect(throws: ControlError.unreadable("cut.png")) {
      try store.setImage(data: Data(cut), name: "cut.png", source: .pasteboard)
    }
    #expect(store.inputs.image == nil)
    #expect(copies(in: root).isEmpty)
  }

  @Test func thePreviewCanBeRenderedAwayFromTheMainActor() async throws {
    let store = store(in: folder())
    #expect(store.previewRequest(maxPixel: 100) == nil)
    try store.setImage(data: pictureData(width: 800, height: 400), name: "a.png", source: .pasteboard)
    let request = try #require(store.previewRequest(maxPixel: 100))
    let preview = await Task.detached { request.render() }.value
    #expect(preview?.width == 100 && preview?.height == 50)
  }

  @Test func aBigPhotoAndATinyPictureBothFillTheCanvas() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 3000, height: 2000), name: "big.png", source: .pasteboard)
    let reduced = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().image)
    #expect(reduced.width == 256 && reduced.height == 256)
    try store.setImage(data: pictureData(width: 40, height: 30), name: "tiny.png", source: .pasteboard)
    let enlarged = try #require(try store.pendingInputs(canvasWidth: 512, canvasHeight: 384).render().image)
    #expect(enlarged.width == 512 && enlarged.height == 384)
  }

  @Test func aCopyThatVanishedBeforeTheRunIsReported() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control/\(try #require(store.inputs.image).fileName)"))
    #expect(throws: ControlError.unreadable("a.png")) { try store.pendingInputs(canvasWidth: 64, canvasHeight: 64).render() }
  }

  // MARK: Moodboard

  func addPictures(_ store: ControlStore, _ count: Int) throws {
    for number in 1...count {
      try store.addMoodboardImage(
        data: pictureData(width: 40 + number, height: 30), name: "m\(number).png", source: .pasteboard)
    }
  }

  @Test func moodboardPicturesAreCopiedInOrderAndStartOn() throws {
    let root = folder()
    let store = store(in: root)
    try addPictures(store, 3)
    #expect(store.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png", "m3.png"])
    #expect(store.inputs.moodboard.allSatisfy { $0.isOn })
    #expect(copies(in: root).count == 3)
  }

  @Test func theSwitchTurnsAPictureOffWithoutLosingIt() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    let second = store.inputs.moodboard[1].id
    store.setMoodboardOn(id: second, isOn: false)
    #expect(store.inputs.moodboard.map(\.isOn) == [true, false, true])
    store.setMoodboardOn(id: second, isOn: true)
    #expect(store.inputs.moodboard.allSatisfy { $0.isOn })
  }

  @Test func removingAMoodboardPictureCanBeUndone() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    let removed = store.inputs.moodboard[0]
    store.removeMoodboardImage(id: removed.id)
    #expect(store.inputs.moodboard.count == 2)
    #expect(store.notice == .removed(name: "m1.png"))
    store.undo()
    #expect(store.inputs.moodboard.first == removed)
    #expect(store.inputs.moodboard.count == 3)
  }

  @Test func replacingAPictureKeepsItsPlaceAndSwitch() throws {
    let root = folder()
    let store = store(in: root)
    try addPictures(store, 2)
    let target = store.inputs.moodboard[0].id
    store.setMoodboardOn(id: target, isOn: false)
    let before = store.inputs.moodboard[0]
    try store.replaceMoodboardImage(id: target, data: pictureData(width: 20, height: 20), name: "new.png", source: .result)
    let after = store.inputs.moodboard[0]
    #expect(after.image.name == "new.png" && after.image.source == .result)
    #expect(after.isOn == false && after.isOn == before.isOn)
    #expect(after.id != before.id)
    #expect(store.inputs.moodboard.count == 2)
    #expect(store.notice == .replaced(name: "m1.png"))
    store.undo()
    #expect(store.inputs.moodboard[0] == before)
  }

  @Test func picturesCanBeReordered() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    let ids = store.inputs.moodboard.map(\.id)
    store.moveMoodboardImage(id: ids[2], before: ids[0])
    #expect(store.inputs.moodboard.map(\.id) == [ids[2], ids[0], ids[1]])
    store.moveMoodboardImage(id: ids[2], before: nil)
    #expect(store.inputs.moodboard.map(\.id) == [ids[0], ids[1], ids[2]])
    store.moveMoodboardImage(id: ids[0], before: ids[0])
    #expect(store.inputs.moodboard.map(\.id) == [ids[0], ids[1], ids[2]])
  }

  @Test func theMoodboardComesBackAtTheNextLaunchAndLostCopiesAreDropped() throws {
    let root = folder()
    let first = store(in: root)
    try addPictures(first, 3)
    first.setMoodboardOn(id: first.inputs.moodboard[1].id, isOn: false)
    let second = store(in: root)
    #expect(second.inputs.moodboard == first.inputs.moodboard)
    #expect(second.notice == nil)
    try FileManager.default.removeItem(
      at: root.appendingPathComponent("Control/\(first.inputs.moodboard[2].image.fileName)"))
    let third = store(in: root)
    #expect(third.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png"])
    #expect(third.notice == .missingAtLaunch(name: "m3.png"))
  }

  @Test func theMoodboardAloneCanBeClearedAndUndone() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    try addPictures(store, 2)
    store.clearMoodboard()
    #expect(store.inputs.moodboard.isEmpty && store.inputs.image?.name == "a.png")
    #expect(store.notice == .cleared)
    store.clearMoodboard()
    #expect(store.canUndo)
    store.undo()
    #expect(store.inputs.moodboard.count == 2)
  }

  @Test func undoingAnAddKeepsTheSwitchesTheUserSet() throws {
    let store = store(in: folder())
    try addPictures(store, 2)
    let first = store.inputs.moodboard[0].id
    store.setMoodboardOn(id: first, isOn: false)
    store.undo()
    #expect(store.inputs.moodboard.map(\.image.name) == ["m1.png"])
    #expect(store.inputs.moodboard[0].isOn == false)
    store.setMoodboardOn(id: first, isOn: true)
    store.redo()
    #expect(store.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png"])
    #expect(store.inputs.moodboard[0].isOn == true)
  }

  @Test func undoKeepsTheOrderTheUserGave() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    let ids = store.inputs.moodboard.map(\.id)
    try store.addMoodboardImage(data: pictureData(width: 50, height: 30), name: "m4.png", source: .pasteboard)
    store.moveMoodboardImage(id: ids[2], before: ids[0])
    #expect(store.inputs.moodboard.map(\.image.name) == ["m3.png", "m1.png", "m2.png", "m4.png"])
    store.undo()
    #expect(store.inputs.moodboard.map(\.image.name) == ["m3.png", "m1.png", "m2.png"])
  }

  @Test func aRemovedPictureComesBackWhereItWasWithItsSwitch() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    let second = store.inputs.moodboard[1].id
    store.setMoodboardOn(id: second, isOn: false)
    store.removeMoodboardImage(id: second)
    store.undo()
    #expect(store.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png", "m3.png"])
    #expect(store.inputs.moodboard.map(\.isOn) == [true, false, true])
  }

  @Test func clearingTakesTheMoodboardOutToo() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    try addPictures(store, 2)
    store.clear()
    #expect(store.inputs == ControlInputs())
    store.undo()
    #expect(store.inputs.moodboard.count == 2 && store.inputs.image != nil)
    #expect(copies(in: root).count == 3)
  }

  @Test func anUnreadableMoodboardFileIsRefusedAndLeavesNothing() throws {
    let root = folder()
    let store = store(in: root)
    #expect(throws: ControlError.unreadable("x.txt")) {
      try store.addMoodboardImage(data: Data("no".utf8), name: "x.txt", source: .pasteboard)
    }
    #expect(store.inputs.moodboard.isEmpty && copies(in: root).isEmpty)
  }

  @Test func aMoodboardFileFromTheFinderIsTakenAsAFile() async throws {
    let root = folder()
    let store = store(in: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("style.png")
    try pictureData(width: 50, height: 40).write(to: file)
    try await store.addMoodboardImage(fileURL: file)
    #expect(store.inputs.moodboard.first?.image.source == .file(path: file.path))
    try await store.addMoodboardImage(fileURL: file, source: .result)
    #expect(store.inputs.moodboard.last?.image.source == .result)
    await #expect(throws: ControlError.unreadable("missing.png")) {
      try await store.addMoodboardImage(fileURL: root.appendingPathComponent("missing.png"))
    }
  }

  @Test func theCopyOfAPictureCanBeDraggedOut() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    let image = try #require(store.inputs.image)
    let url = try #require(store.copyURL(of: image))
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(url.lastPathComponent == image.fileName)
  }

  @Test func theRunSendsTheMoodboardPicturesThatAreOnAllWithTheSameWeight() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    store.setMoodboardOn(id: store.inputs.moodboard[1].id, isOn: false)
    let inputs = try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render()
    #expect(inputs.image == nil)
    #expect(inputs.hints.count == 2 && inputs.hints.allSatisfy { $0.weight == 1 })
    for hint in inputs.hints {
      let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
      #expect(CGImageSourceGetCount(source) == 1)
    }
    #expect(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256, includeMoodboard: false).render().isEmpty)
  }

  @Test func aBigMoodboardPictureIsSentReduced() throws {
    let store = store(in: folder())
    try store.addMoodboardImage(data: pictureData(width: 3000, height: 2000), name: "big.png", source: .pasteboard)
    let hint = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().hints.first)
    let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) == 1024)
    #expect(image.width > image.height)
  }

  @Test func aMoodboardCopyThatVanishedBeforeTheRunIsReported() throws {
    let root = folder()
    let store = store(in: root)
    try addPictures(store, 1)
    try FileManager.default.removeItem(
      at: root.appendingPathComponent("Control/\(store.inputs.moodboard[0].image.fileName)"))
    #expect(throws: ControlError.unreadable("m1.png")) {
      try store.pendingInputs(canvasWidth: 64, canvasHeight: 64).render()
    }
  }

  @Test func manyReferencesAndAFamilyThatIgnoresThemAreReported() throws {
    let store = store(in: folder())
    try addPictures(store, 3)
    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512).isEmpty)
    try addPictures(store, 1)
    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512) == [.manyReferences(count: 4)])
    store.setMoodboardOn(id: store.inputs.moodboard[0].id, isOn: false)
    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512).isEmpty)
    #expect(
      store.warnings(canvasWidth: 512, canvasHeight: 512, usesMoodboard: false) == [.moodboardIgnored])
    let empty = ControlStore(storage: FileReferenceStorage(folder: folder()), fileURL: folder().appendingPathComponent("c.json"))
    #expect(empty.warnings(canvasWidth: 512, canvasHeight: 512, usesMoodboard: false).isEmpty)
  }
}
