import AppKit
import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct StateTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  private func state(_ storage: MemoryStorage = MemoryStorage()) -> EditState {
    EditState(store: EditStore(storage: storage), italian: false, imageSize: { _ in CGSize(width: 300, height: 200) })
  }

  private func context(start: String? = "/s/start.png", moodboard: [String] = ["/s/a.png", "/s/b.png"], window: Bool = true) throws
    -> DTHubContext
  {
    var json = #"{"type":"context","tempFolder":"/t","parameters":{"width":2048,"height":1664}"#
    if let start { json += #","startImage":"\#(start)""# }
    if !moodboard.isEmpty { json += #","moodboard":[\#(moodboard.map { "\"\($0)\"" }.joined(separator: ","))]"# }
    if window { json += #","startImageWindow":{"x":50,"y":0,"width":200,"height":200}"# }
    return try JSONDecoder().decode(DTHubContext.self, from: Data((json + "}").utf8))
  }

  @Test func contextBuildsTheReferencesInOrderAndTheCanvas() throws {
    let s = state()
    s.update(context: try context())
    #expect(s.refs.map(\.number) == [1, 2] && s.refs.map(\.fileName) == ["a.png", "b.png"])
    #expect(s.startImage?.path == "/s/start.png" && s.startSize == CGSize(width: 300, height: 200))
    #expect(s.generationSize == CGSize(width: 2048, height: 1664))
    #expect(s.window == DTHubImageWindow(x: 50, y: 0, width: 200, height: 200))
    #expect(s.startGeometry.canvasAspect == 2048.0 / 1664.0)
    #expect(s.referenceGeometry(of: s.refs[0]).canvasAspect == 1.5)
  }

  @Test func drawingOnTheShownReferenceUsesItsFile() throws {
    let s = state()
    s.update(context: try context())
    s.showReference(by: 1)
    s.drawOnReference(box(100, 100, 400, 400))
    #expect(s.document.elements.first?.refFile == "b.png")
    #expect(s.selected == s.document.elements.first?.id)
    #expect(s.elementsOnShownReference.count == 1)
    s.showReference(by: -1)
    #expect(s.elementsOnShownReference.isEmpty)
  }

  @Test func drawingOnAReferenceWithoutOneDoesNothing() throws {
    let s = state()
    s.update(context: try context(moodboard: []))
    s.drawOnReference(box(100, 100, 400, 400))
    #expect(s.document.elements.isEmpty && s.currentReference == nil)
  }

  @Test func theShownReferenceIsClampedWhenTheMoodboardShrinks() throws {
    let s = state()
    s.update(context: try context())
    s.showReference(by: 5)
    #expect(s.currentReference?.fileName == "b.png" && s.document.referenceIndex == 1)
    s.update(context: try context(moodboard: ["/s/a.png"]))
    #expect(s.currentReference?.fileName == "a.png" && s.document.referenceIndex == 0)
    s.update(context: try context(moodboard: []))
    #expect(s.currentReference == nil && s.document.referenceIndex == 0)
  }

  @Test func missingImageKeepsTheElementButBlocksSending() throws {
    let s = state()
    s.active = true
    s.update(context: try context())
    s.showReference(by: 1)
    s.drawOnReference(box(100, 100, 400, 400))
    s.document.elements[0].desc = "A lamp"
    #expect(s.canSend)
    s.update(context: try context(moodboard: ["/s/a.png"]))
    #expect(s.document.elements.count == 1)
    #expect(s.problems == [.imageMissing(s.document.elements[0].id)])
    #expect(!s.canSend)
    #expect(!s.sendText.contains("\"desc\": \"A lamp\""))
    // Turned on again, it comes back.
    s.update(context: try context())
    #expect(s.canSend)
  }

  @Test func reorderingTheMoodboardRenumbersWithoutMovingTheElement() throws {
    let s = state()
    s.update(context: try context())
    s.drawOnReference(box(100, 100, 400, 400))
    s.document.elements[0].desc = "x"
    #expect(s.sendText.contains("\"from\": \"ref_image_1\""))
    s.update(context: try context(moodboard: ["/s/b.png", "/s/a.png"]))
    #expect(s.sendText.contains("\"from\": \"ref_image_2\""))
  }

  @Test func withoutAStartImageSendingIsBlocked() throws {
    let s = state()
    s.active = true
    s.update(context: try context(start: nil))
    s.document.draw(onCanvas: box(0, 0, 100, 100))
    s.document.elements[0].desc = "x"
    #expect(s.problems.contains(.noStartImage) && !s.canSend)
  }

  @Test func theWindowMissingIsSaidNotHidden() throws {
    let s = state()
    s.update(context: try context(window: false))
    #expect(s.windowNote == L.text(.noWindow, italian: false))
    s.update(context: try context(window: true))
    #expect(s.windowNote == nil)
    s.update(context: try context(start: nil, window: false))
    #expect(s.windowNote == nil)
  }

  @Test func selectingAnElementSelectsItEverywhere() throws {
    let s = state()
    s.document.draw(onCanvas: box(0, 0, 100, 100))
    s.document.draw(onCanvas: box(200, 200, 300, 300))
    s.select("el_2")
    #expect(s.selected == "el_2")
    s.document.delete("el_2")
    s.update(context: try context())
    #expect(s.selected == nil)
  }

  private func picture(width: Int, height: Int, in folder: URL) throws -> URL {
    let url = folder.appendingPathComponent("f3e-\(UUID().uuidString)-p.png")
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  @Test func thePicturesAlwaysGo_theStartAsTheCanvasAndTheUsedReferencesWhole() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-tmp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let start = try picture(width: 300, height: 200, in: temp)
    let first = try picture(width: 300, height: 200, in: temp), unused = try picture(width: 300, height: 200, in: temp)
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"\#(temp.path)","parameters":{"width":1024,"height":512},"startImage":"\#(start.path)","moodboard":["\#(first.path)","\#(unused.path)"]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    s.drawOnReference(box(100, 100, 600, 600))  // sulla prima reference
    s.drawOnCanvas(box(0, 0, 100, 100))
    let pictures = s.llmPictures()
    #expect(pictures.map(\.number) == [0, 1])  // the second reference is not used: it stays home
    #expect(pictures.map(\.role) == [.start, .reference])
    #expect(pictures.allSatisfy { FileManager.default.fileExists(atPath: $0.path) && $0.path.hasPrefix(temp.path) })
    #expect(ImageSizes.read(path: pictures[0].path) == CGSize(width: 1024, height: 512))  // the canvas: the shape of the Generation
    #expect(ImageSizes.read(path: pictures[1].path) == CGSize(width: 1024, height: 683))  // the reference: its own shape
  }

  @Test func withoutAStartImageOrAReadableOneThePictureIsLeftOutWithoutFailing() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-tmp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let ref = try picture(width: 300, height: 200, in: temp)
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"\#(temp.path)","startImage":"/nonexistent/start.png","moodboard":["\#(ref.path)"]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    s.drawOnReference(box(100, 100, 600, 600))
    #expect(s.llmPictures().map(\.number) == [1])  // the unreadable start picture is skipped
  }

  @Test func tooManyReferencesAreLeftOutAndNamed() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-tmp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let files = try (0..<6).map { _ in try picture(width: 300, height: 200, in: temp) }
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"\#(temp.path)","startImage":"/s/start.png","moodboard":[\#(files.map { "\"\($0.path)\"" }.joined(separator: ","))]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    for index in 0..<6 {
      if index > 0 { s.showReference(by: 1) }
      s.drawOnReference(box(100, 100, 600, 600))
    }
    #expect(s.droppedPictures == [6])  // the start picture plus five references is the most that goes along
  }

  @Test func theTagColorsAreThoseOfTheElements() throws {
    let s = state()
    s.document.draw(onCanvas: box(0, 0, 100, 100))
    s.document.draw(onCanvas: box(200, 200, 300, 300))
    #expect(s.tagColors == ["el_1": 0, "el_2": 1])
  }

  @Test func anOldStateFileWithTheImagesSwitchStillLoads() throws {
    let storage = MemoryStorage()
    let old = #"{"schema":1,"document":{"prose":"kept","elements":[],"referenceIndex":0,"llmImages":true}}"#
    storage.set(Data(old.utf8), forKey: EditStore.key)
    #expect(state(storage).document.prose == "kept")
  }

  @Test func clearingTheTabLeavesItAsNew() throws {
    let s = state()
    s.document.prose = "Modify <ref_image_0> by: adding <el_1>"
    s.document.draw(onCanvas: box(0, 0, 100, 100))
    s.select("el_1")
    #expect(s.canClear)
    s.clear()
    #expect(s.document.elements.isEmpty && s.document.prose == EditDocument.defaultProse && s.selected == nil)
    #expect(!s.canClear)
  }

  @Test func theDefaultSentenceAloneIsNothingToWrite() throws {
    let s = state()
    s.active = true
    #expect(!s.hasWritableContent && !s.canWrite)
    s.document.prose += "adding a lamp"
    #expect(s.hasWritableContent && s.canWrite)
  }

  @Test func undoRestoresOnlyTheLastWrite() throws {
    let s = state()
    s.document.prose = "original prose"
    s.document.draw(onCanvas: box(0, 0, 100, 100))
    s.document.elements[0].desc = "original desc"
    #expect(!s.canUndo)
    s.takeSnapshot()
    #expect(s.canUndo)
    s.document.prose = "rewritten"
    s.document.elements[0].desc = "rewritten desc"
    s.undo()
    #expect(s.document.prose == "original prose" && s.document.elements[0].desc == "original desc")
    #expect(s.document.snapshot == nil && !s.canUndo)
    #expect(s.status == L.text(.undone, italian: false))
  }

  @Test func stateSurvivesARestart() throws {
    let storage = MemoryStorage()
    let first = state(storage)
    first.document.prose = "Modify <ref_image_0>"
    first.document.draw(onCanvas: box(10, 20, 300, 400))
    let second = state(storage)
    #expect(second.document == first.document)
  }

  @Test func switchingProjectLoadsItsOwnState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let (a, b) = (root.appendingPathComponent("a"), root.appendingPathComponent("b"))
    let s = state()
    s.switchProject(folder: a, adoptLegacy: false)
    s.document.prose = "in A"
    s.switchProject(folder: b, adoptLegacy: false)
    #expect(s.document.prose == EditDocument.defaultProse)
    s.document.prose = "in B"
    s.switchProject(folder: a, adoptLegacy: false)
    #expect(s.document.prose == "in A")
    s.switchProject(folder: b, adoptLegacy: false)
    #expect(s.document.prose == "in B")
  }
}
