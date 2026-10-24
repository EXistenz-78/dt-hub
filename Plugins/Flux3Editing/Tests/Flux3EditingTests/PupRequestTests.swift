import AppKit
import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct PupRequestTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  private func picture(width: Int, height: Int, in folder: URL) throws -> URL {
    let rep = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let url = folder.appendingPathComponent("p-\(UUID().uuidString).png")
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-pup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  @Test func messageHasTheOfficialScaffold() {
    let locked = [PupRow(id: "el_2", from: "ref_image_1", src: [1, 2, 30, 40], tgt: [5, 6, 70, 80], desc: "A ninja")]
    let message = PupRequest.message(prose: "Modify <ref_image_0> by adding <el_2>.", locked: locked)
    #expect(message.hasPrefix("Reference images follow in attachment order: ref_image_0, ref_image_1, ...\nUser editing instruction: ORIGINAL PROMPT:\nModify <ref_image_0> by adding <el_2>.\n\nLOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:\n"))
    #expect(message.contains(PupRecord.json(locked)))
    #expect(message.hasSuffix("\nDecide the edit, imagine the target image, and output the annotation record."))
  }

  @Test func aReminderComesBeforeTheClosingLine() {
    let message = PupRequest.message(prose: "p", locked: [], reminder: "REMIND")
    #expect(message.contains("REMIND\nDecide the edit"))
  }

  @Test func optionsAreTheOfficialOnes() {
    let o = PupRequest.options
    #expect(o.temperature == 0 && o.topP == 0.95 && o.topK == 20 && o.presencePenalty == 0)
    #expect(o.maxTokens == 3584 && o.thinking == false && o.timeout == 600)
  }

  @Test func sizeMatchesBFLForOneTwoAndThreeImages() {
    #expect(PupImages.size(width: 1024, height: 640, count: 1) == (1024, 640))
    #expect(PupImages.size(width: 1024, height: 640, count: 2) == (896, 544))
    #expect(PupImages.size(width: 1024, height: 640, count: 3) == (640, 384))
    #expect(PupImages.size(width: 300, height: 200, count: 1) == (288, 192))  // half-way cases round to even, as Python does
  }

  @Test func lockedRowsUseTargetForNewObjectsAndSkipMissingReferences() {
    var doc = EditDocument()
    doc.draw(onCanvas: box(0, 0, 100, 100))
    doc.draw(onReference: "gone.png", box: box(10, 10, 200, 200))
    doc.draw(onReference: "a.png", box: box(20, 30, 400, 500))
    doc.elements[0].desc = "a new thing"
    let refs = [RefImage(number: 1, path: "/s/a.png", size: CGSize(width: 300, height: 200))]
    let rows = EditComposer.lockedRows(doc, refs: refs)
    #expect(rows.map(\.id) == ["el_1", "el_3"])
    #expect(rows[0] == PupRow(id: "el_1", from: "target", src: nil, tgt: [0, 0, 100, 100], desc: "a new thing"))
    #expect(rows[1].from == "ref_image_1" && rows[1].src == [20, 30, 400, 500] && rows[1].tgt != nil)
  }

  @Test func prepareWritesJpegsAtThePolicySize() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let start = try picture(width: 1024, height: 640, in: folder), ref = try picture(width: 446, height: 448, in: folder)
    let pictures = PupImages.prepare(sources: [(0, start.path), (1, ref.path)], to: folder)
    #expect(pictures.map(\.number) == [0, 1] && pictures.map(\.role) == [.start, .reference])
    #expect(pictures.allSatisfy { $0.path.hasSuffix(".jpg") && FileManager.default.fileExists(atPath: $0.path) })
    #expect(ImageSizes.read(path: pictures[0].path) == CGSize(width: 896, height: 544))
    #expect(ImageSizes.read(path: pictures[1].path) == CGSize(width: 448, height: 448))
  }

  @Test func prepareSkipsAnUnreadableSource() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let ref = try picture(width: 300, height: 200, in: folder)
    let pictures = PupImages.prepare(sources: [(0, "/nonexistent.png"), (1, ref.path)], to: folder)
    #expect(pictures.map(\.number) == [1])
  }

  @Test func theStateSendsTheStartAsTheCanvasAndEveryReferenceUpToTheLastUsedOne() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let start = try picture(width: 300, height: 200, in: folder)
    let files = try (0..<3).map { _ in try picture(width: 300, height: 200, in: folder) }
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"\#(folder.path)","parameters":{"width":1024,"height":512},"startImage":"\#(start.path)","moodboard":[\#(files.map { "\"\($0.path)\"" }.joined(separator: ","))]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    s.showReference(by: 2)
    s.drawOnReference(box(100, 100, 600, 600))  // only the third reference is used
    let pictures = s.pupPictures()
    #expect(pictures.map(\.number) == [0, 1, 2, 3])  // the numbers of <ref_image_N> must match the attachment order
    #expect(pictures.allSatisfy { $0.path.hasSuffix(".jpg") })
  }

  @Test func theStateGivesNoPicturesWhenOneCannotBeReadBecauseTheNumbersWouldShift() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let ref = try picture(width: 300, height: 200, in: folder)
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"\#(folder.path)","startImage":"/nonexistent/start.png","moodboard":["\#(ref.path)"]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    s.drawOnReference(box(100, 100, 600, 600))
    #expect(s.pupPictures().isEmpty)
  }
}
