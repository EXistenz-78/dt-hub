import Foundation
import Testing

@testable import Flux3Editing

enum PupFixture {
  static func text(_ name: String) throws -> String {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    return try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static let locked = PupRow(
    id: "el_2", from: "ref_image_1", src: [78, 92, 974, 950], tgt: [488, 67, 952, 379], desc: "un nninja che si muove tra i bamboo")
}

struct PupRecordTests {
  @Test func splitTakesTheLastValidList() throws {
    let (caption, rows) = PupRecord.split(try PupFixture.text("pup_blur.txt"))
    #expect(caption.hasPrefix("Add the black-clad ninja warrior <ninja_1>"))
    #expect(!caption.contains("\"id\""))
    #expect(rows?.map(\.id) == ["person_1", "ninja_1"])
    #expect(rows?[1].from == "ref_image_1" && rows?[1].src == [78, 92, 974, 950] && rows?[1].tgt == [488, 67, 952, 379])
  }

  @Test func splitIgnoresBracketsInsideDescsAndInTheCaption() {
    let text = #"Put the sign "[SALE]" <sign_1> on the door. [{"id":"sign_1","from":"target","src_bbox":null,"tgt_bbox":[10,20,300,400],"desc":"A sign saying \"[SALE]\" with a [bracket] note."}]"#
    let (caption, rows) = PupRecord.split(text)
    #expect(caption == #"Put the sign "[SALE]" <sign_1> on the door."#)
    #expect(rows?.count == 1 && rows?[0].from == "target" && rows?[0].src == nil)
  }

  @Test func splitWithoutAListGivesNilRows() {
    let (caption, rows) = PupRecord.split("Just a caption [SALE]")
    #expect(caption == "Just a caption [SALE]" && rows == nil)
  }

  @Test func reconcileRenamesAnIdWithTheSameBoxToOurs() throws {
    let result = PupReconcile.reconcile(try PupFixture.text("pup_blur.txt"), locked: [PupFixture.locked])
    #expect(result.caption.contains("<el_2>") && !result.caption.contains("<ninja_1>"))
    #expect(result.rows.map(\.id) == ["el_2"])
  }

  @Test func ourRowsKeepIdFromAndBoxesAndTakeTheModelsDesc() throws {
    let result = PupReconcile.reconcile(try PupFixture.text("pup_blur.txt"), locked: [PupFixture.locked])
    let row = try #require(result.rows.first)
    #expect(row.from == "ref_image_1" && row.src == [78, 92, 974, 950] && row.tgt == [488, 67, 952, 379])
    #expect(row.desc.hasPrefix("An adult male ninja warrior"))
  }

  @Test func anAddedRowIsKeptWhenValid() throws {
    let result = PupReconcile.reconcile(try PupFixture.text("pup_blur.txt"), locked: [PupFixture.locked])
    #expect(result.added.map(\.id) == ["person_1"])
    #expect(result.added[0].from == "ref_image_0" && result.added[0].src == [313, 468, 1000, 833])
  }

  @Test func anAddedRowIsDroppedWhenNotCitedOrInvalid() {
    func added(_ row: String, caption: String = "Edit <el_2> and <extra_1>.") -> [PupRow] {
      let own = #"{"id":"el_2","from":"ref_image_1","src_bbox":[78,92,974,950],"tgt_bbox":[488,67,952,379],"desc":"d"}"#
      return PupReconcile.reconcile("\(caption) [\(own),\(row)]", locked: [PupFixture.locked]).added
    }
    let good = #"{"id":"extra_1","from":"ref_image_0","src_bbox":[10,10,200,200],"tgt_bbox":[10,10,200,200],"desc":"x"}"#
    #expect(added(good).count == 1)
    #expect(added(good, caption: "Edit <el_2>.").isEmpty)  // not cited
    #expect(added(good.replacingOccurrences(of: "[10,10,200,200]", with: "[10,10,2000,200]")).isEmpty)  // out of the grid
    #expect(added(good.replacingOccurrences(of: "ref_image_0", with: "target")).isEmpty)  // target with a source box
    #expect(added(good.replacingOccurrences(of: #""desc":"x""#, with: #""desc":"  ""#)).isEmpty)  // empty desc
  }

  @Test func aLockedRowMissingInTheAnswerKeepsItsOwnDesc() {
    let result = PupReconcile.reconcile("Edit <el_2>. []", locked: [PupFixture.locked])
    #expect(result.rows.map(\.desc) == [PupFixture.locked.desc])
  }

  @Test func iouAndBoxValidity() {
    #expect(PupReconcile.iou([0, 0, 100, 100], [0, 0, 100, 100]) == 1)
    #expect(PupReconcile.iou([0, 0, 100, 100], [200, 200, 300, 300]) == 0)
    #expect(!PupReconcile.validBox([0, 0, 1, 1]))  // 0–1 coordinates, not the grid
    #expect(!PupReconcile.validBox([50, 50, 40, 60]) && !PupReconcile.validBox(nil) && PupReconcile.validBox([0, 0, 1000, 1000]))
  }

  @Test func jsonIsOneLineWithExplicitNulls() {
    let line = PupRecord.json([PupRow(id: "a", from: nil, src: nil, tgt: [1, 2, 30, 40], desc: "x \"y\" /z")])
    #expect(line == #"[{"id":"a","from":null,"src_bbox":null,"tgt_bbox":[1,2,30,40],"desc":"x \"y\" /z"}]"#)
  }
}
