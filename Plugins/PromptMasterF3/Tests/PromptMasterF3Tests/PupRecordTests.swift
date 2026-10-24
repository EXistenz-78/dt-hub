import Foundation
import Testing

@testable import PromptMasterF3

enum PupFixture {
  static func text(_ name: String) throws -> String {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    return try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static let lantern = PupRow(id: "lantern_1", bbox: [389, 807, 991, 956], desc: "una lanterna di pietra con muschio")
  static let cat = PupRow(id: "cat_1", bbox: [700, 420, 990, 560], desc: "un gatto nero")
}

struct PupRecordTests {
  @Test func splitTakesTheFinalTable() throws {
    let (caption, rows) = PupRecord.split(try PupFixture.text("pup_t2i.txt"))
    #expect(caption.hasPrefix("Full-color outdoor photograph") && !caption.contains("\"id\""))
    #expect(rows?.map(\.id) == ["parasol_1", "person_1", "forest_1", "lantern_1", "cat_1"])
    #expect(rows?[3].bbox == [389, 807, 991, 956])
  }

  @Test func splitIgnoresBracketsInTheCaptionAndInDescs() {
    let text = #"A sign "[SALE]" <sign_1>. [{"id": "sign_1", "bbox": [10, 20, 300, 400], "desc": "A sign with a [bracket] note."}]"#
    let (caption, rows) = PupRecord.split(text)
    #expect(caption == #"A sign "[SALE]" <sign_1>."# && rows?.count == 1)
  }

  @Test func splitStripsFencesAndSkipsAListOfNumbers() {
    let fenced = "Edit <a_1>.\n```json\n[{\"id\": \"a_1\", \"bbox\": [1, 2, 30, 40], \"desc\": \"d\"}]\n```"
    #expect(PupRecord.split(fenced).rows?.map(\.id) == ["a_1"])
    #expect(PupRecord.split("Edit <a_1>. [1, 2, 3, 4]").rows == nil)
    #expect(PupRecord.split("No table here.").rows == nil)
  }

  @Test func reconcileKeepsOurRowsAndTakesTheModelsDescs() throws {
    let result = PupReconcile.reconcile(try PupFixture.text("pup_t2i.txt"), locked: [PupFixture.lantern, PupFixture.cat])
    #expect(result.rows.map(\.id) == ["lantern_1", "cat_1"])
    #expect(result.rows[0].bbox == [389, 807, 991, 956] && result.rows[0].desc.hasPrefix("A tall weathered stone lantern"))
    #expect(result.hadList)
  }

  @Test func addedRowsAreKeptWhenCitedAndWellFormed() throws {
    let result = PupReconcile.reconcile(try PupFixture.text("pup_t2i.txt"), locked: [PupFixture.lantern, PupFixture.cat])
    #expect(result.added.map(\.id) == ["parasol_1", "person_1", "forest_1"])
    #expect(result.added[2].bbox == [0, 0, 1000, 1000])
  }

  @Test func anAddedRowIsDroppedWhenNotCitedOrInvalid() {
    func added(_ row: String, caption: String = "A <lantern_1> and <extra_1>.") -> [PupRow] {
      let own = #"{"id": "lantern_1", "bbox": [389, 807, 991, 956], "desc": "d"}"#
      return PupReconcile.reconcile("\(caption) [\(own), \(row)]", locked: [PupFixture.lantern]).added
    }
    let good = #"{"id": "extra_1", "bbox": [10, 10, 200, 200], "desc": "x"}"#
    #expect(added(good).count == 1)
    #expect(added(good, caption: "A <lantern_1>.").isEmpty)
    #expect(added(good.replacingOccurrences(of: "[10, 10, 200, 200]", with: "[10, 10, 2000, 200]")).isEmpty)
    #expect(added(good.replacingOccurrences(of: "[10, 10, 200, 200]", with: "[0, 0, 1, 1]")).isEmpty)
    #expect(added(good.replacingOccurrences(of: #""desc": "x""#, with: #""desc": " ""#)).isEmpty)
  }

  @Test func aRowThatRePlansOurBoxTakesOurId() {
    let text = #"A stone lantern <stone_lantern_1>. [{"id": "stone_lantern_1", "bbox": [389, 807, 991, 956], "desc": "A mossy lantern."}]"#
    let result = PupReconcile.reconcile(text, locked: [PupFixture.lantern])
    #expect(result.caption.contains("<lantern_1>") && !result.caption.contains("stone_lantern_1"))
    #expect(result.rows[0].desc == "A mossy lantern." && result.added.isEmpty)
  }

  @Test func aLockedRowMissingFromTheAnswerKeepsItsOwnDesc() {
    let result = PupReconcile.reconcile("A <lantern_1>. []", locked: [PupFixture.lantern])
    #expect(result.rows.map(\.desc) == [PupFixture.lantern.desc])
  }

  @Test func jsonIsOneLineWithPythonsSpacing() {
    let line = PupRecord.json([PupRow(id: "a", bbox: [1, 2, 30, 40], desc: "x \"y\" /z")])
    #expect(line == #"[{"id": "a", "bbox": [1, 2, 30, 40], "desc": "x \"y\" /z"}]"#)
  }
}
