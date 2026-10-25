import CoreGraphics
import ImageIO
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Sticker card")
struct PSStickerCardTests {
  func openState() -> (PSState, URL) {
    let project = TestImages.tempFolder()
    let state = PSState(italian: false)
    state.switchProject(folder: project)
    return (state, project)
  }

  func pictures(_ count: Int, in folder: URL, focal35: Double? = nil) -> [URL] {
    (0..<count).map { i in
      var properties: [CFString: Any] = [:]
      if let focal35 { properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifFocalLenIn35mmFilm: Int(focal35), kCGImagePropertyExifPixelXDimension: 90, kCGImagePropertyExifPixelYDimension: 60] }
      return TestImages.file(TestImages.solid(90, 60, UInt8(40 * i), 80, 120), in: folder, name: "p\(i).jpg", properties: properties)
    }
  }

  @Test func dropOfThreeFilesMakesThreeCascadingStickers() {
    let (state, _) = openState()
    state.addStickers(from: pictures(3, in: TestImages.tempFolder()))
    #expect(state.doc.stickers.count == 3)
    #expect(state.doc.stickers.map(\.yaw) == [0, 10, 20])
    #expect(state.doc.stickers.map(\.hfov) == [60, 60, 60])
    #expect(state.doc.selectedID == state.doc.stickers[2].id)
    #expect(state.doc.stickers.allSatisfy { state.image(for: $0) != nil })
  }

  @Test func theExifFocalSetsTheStartingFieldOfView() {
    let (state, _) = openState()
    state.addStickers(from: pictures(1, in: TestImages.tempFolder(), focal35: 28))
    #expect(abs(state.doc.stickers[0].hfov - 65.5) < 0.1)
  }

  @Test func aBadFileDoesNotStopTheOthersAndIsNamed() throws {
    let (state, _) = openState()
    let folder = TestImages.tempFolder()
    let bad = folder.appendingPathComponent("bad.png")
    try Data().write(to: bad)
    state.addStickers(from: [pictures(1, in: folder)[0], bad])
    #expect(state.doc.stickers.count == 1)
    #expect(state.notice?.contains("bad.png") == true)
  }

  @Test func withoutAProjectNothingIsAddedAndTheUserIsTold() {
    let state = PSState(italian: false)
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    #expect(state.doc.stickers.isEmpty && state.notice != nil)
  }

  @Test func aCroppedPhotoGetsANoteAndTheDefaultFOV() {
    let (state, _) = openState()
    state.addPicture = { url, project in
      var added = try PSStickerStore.add(contentsOf: url, into: project)
      added.suggestedHFOV = nil
      added.looksCropped = true
      return added
    }
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    #expect(state.doc.stickers[0].hfov == 60 && state.notice?.contains("p0.jpg") == true)
  }

  @Test func reorderPutsARowInFrontOfTheTarget() {
    let (state, _) = openState()
    state.addStickers(from: pictures(3, in: TestImages.tempFolder()))
    let ids = state.doc.stickers.map(\.id)
    state.moveSticker(ids[0], inFrontOf: ids[1])
    #expect(state.doc.stickers.map(\.id) == [ids[1], ids[0], ids[2]])
    state.moveSticker(ids[2], inFrontOf: ids[2])
    #expect(state.doc.stickers.map(\.id) == [ids[1], ids[0], ids[2]])
  }

  @Test func deletingAStickerRemovesItsFileButADuplicateKeepsTheSharedOne() {
    let (state, project) = openState()
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    let file = project.appendingPathComponent(state.doc.stickers[0].file).path
    state.duplicateSelected()
    #expect(state.doc.stickers.count == 2)
    state.deleteSelected()
    #expect(FileManager.default.fileExists(atPath: file))
    state.deleteSelected()
    #expect(!FileManager.default.fileExists(atPath: file))
  }

  @Test func clearAllRemovesTheFiles() {
    let (state, project) = openState()
    state.addStickers(from: pictures(2, in: TestImages.tempFolder()))
    let files = state.doc.stickers.map { project.appendingPathComponent($0.file).path }
    state.clearAll()
    #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
  }

  @Test func fieldsClampTheirValues() {
    let (state, _) = openState()
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    let id = state.doc.stickers[0].id
    state.binding(id, \.hfov).wrappedValue = 200
    state.binding(id, \.pitch).wrappedValue = 95
    state.binding(id, \.opacity).wrappedValue = 2
    state.binding(id, \.yaw).wrappedValue = 190
    let s = state.sticker(id)!
    #expect(s.hfov == 170 && s.pitch == 89 && s.opacity == 1 && abs(s.yaw - (-170)) < 1e-9)
    state.binding(id, \.hfov).wrappedValue = 1
    #expect(state.sticker(id)!.hfov == 5)
  }

  @Test func theVerticalFOVIsReadFromThePictureProportions() {
    let (state, _) = openState()
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    let s = state.doc.stickers[0]
    #expect(abs(state.verticalFOV(of: s) - PSProjection.verticalFOV(hfov: 60, aspect: 1.5)) < 1e-9)
  }

  @Test func visibilityToggles() {
    let (state, _) = openState()
    state.addStickers(from: pictures(1, in: TestImages.tempFolder()))
    let id = state.doc.stickers[0].id
    state.setVisible(id, false)
    #expect(state.sticker(id)?.visible == false)
  }
}
