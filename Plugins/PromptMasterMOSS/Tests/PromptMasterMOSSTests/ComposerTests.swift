import Foundation
import Testing

@testable import PromptMasterMOSS

/// Un catalogo finto: ordine per id, così i test non dipendono dal database.
struct FakeTerms: MossTerms {
  var meta: [String: String] = ["m_photo": "photograph"]
  var caption: [String: String] = ["c_light": "Dappled sunlight", "c_rim": "rim light"]
  var negative: [(id: String, en: String)] = [
    ("ng_worst_quality", "worst quality"), ("ng_blurry", "blurry"), ("ng_bad_anatomy", "bad anatomy"),
  ]
  func metaTerms(_ selection: Set<String>) -> [String] { meta.keys.sorted().filter(selection.contains).map { meta[$0]! } }
  func captionTerms(_ selection: Set<String>) -> [String] { caption.keys.sorted().filter(selection.contains).map { caption[$0]! } }
  func negativeTerms(_ selection: Set<String>) -> [String] { negative.filter { selection.contains($0.id) }.map(\.en) }
}

struct ComposerTests {
  let size = PixelSize(width: 1024, height: 1024)
  let terms = FakeTerms()

  func item(_ id: Int, _ label: MossLabel = .object, caption: String = "A cup.", text: String = "", tags: String = "", colors: [String] = [], box: FracBox = FracBox(x0: 0.25, y0: 0.25, x1: 0.75, y1: 0.75)) -> MossItem {
    MossItem(id: id, label: label, caption: caption, text: text, tags: tags, colors: colors, box: box, expanded: false)
  }

  @Test func json_keysAreInTheOrderOfTheSpec() {
    var document = MossDocument()
    document.description = "A."
    document.selection = ["m_photo", "c_light", "c_rim"]
    document.freeMeta = ["cinematic"]
    document.palette = ["#2F4F4F"]
    document.items = [
      item(1),
      item(2, .text, caption: "White lettering.", text: "Hi\nthere", tags: "a, b", colors: ["#FFFFFF"], box: FracBox(x0: 0, y0: 0, x1: 0.5, y1: 0.1)),
    ]
    let expected =
      ##"{"summary":{"meta":["photograph","cinematic"],"canvas":"single","palette":["#2F4F4F"],"caption":"A. Dappled sunlight, rim light."},"##
      + ##""items":[{"label":"object","caption":"A cup.","bbox":[-256,-256,256,256]},"##
      + ##"{"label":"text","caption":"White lettering.","text":"Hi\nthere","bbox":[-512,-512,-409,0],"tags":["a","b"],"palette":["#FFFFFF"]}],"##
      + ##""bbox_coord_space":"abs_centralized","bbox_format":"yxyx"}"##
    #expect(MossComposer.json(document, catalog: terms, size: size) == expected)
  }

  @Test func json_omitsEmptyOptionals() {
    var document = MossDocument()
    document.description = "A."
    document.items = [item(1)]
    let expected =
      ##"{"summary":{"canvas":"single","caption":"A."},"items":[{"label":"object","caption":"A cup.","bbox":[-256,-256,256,256]}],"##
      + ##""bbox_coord_space":"abs_centralized","bbox_format":"yxyx"}"##
    #expect(MossComposer.json(document, catalog: terms, size: size) == expected)
  }

  @Test func json_textOnlyOnTextItems() {
    var document = MossDocument()
    document.description = "A."
    document.items = [item(1, .object, text: "stale text"), item(2, .panel, text: "also stale")]
    let json = MossComposer.json(document, catalog: terms, size: size)
    #expect(!json.contains("stale"))
    #expect(!json.contains("\"text\""))
  }

  @Test func json_isOneLine_evenWithNewlinesInTheText() {
    var document = MossDocument()
    document.description = "A.\nB."
    document.items = [item(1, .text, text: "x\ny")]
    #expect(!MossComposer.json(document, catalog: terms, size: size).contains("\n"))
  }

  @Test func negative_isTheTwoDefaultTermsInCatalogOrder() {
    #expect(MossComposer.negative(MossDocument(), catalog: terms) == "worst quality, bad anatomy")
  }

  @Test func negative_joinsChosenTermsThenFreeText() {
    var document = MossDocument()
    document.negativeSelection = ["ng_blurry", "ng_worst_quality"]
    document.negativeText = " ugly , extra fingers "
    #expect(MossComposer.negative(document, catalog: terms) == "worst quality, blurry, ugly , extra fingers")
    document.negativeSelection = []
    document.negativeText = ""
    #expect(MossComposer.negative(document, catalog: terms) == "")
  }

  @Test func problems_flagsEachCase() {
    var document = MossDocument()
    #expect(MossComposer.problems(document, catalog: terms, size: size).contains(.emptySummary))
    #expect(MossComposer.problems(document, catalog: terms, size: size).contains(.noItems))
    document.selection = ["c_light"]  // una voce basta come caption
    #expect(!MossComposer.problems(document, catalog: terms, size: size).contains(.emptySummary))
    document.items = [item(1, caption: "  "), item(2, .text, text: ""), item(3, .object, text: "")]
    let problems = MossComposer.problems(document, catalog: terms, size: size)
    #expect(problems.contains(.emptyCaption(item: 1)))
    #expect(problems.contains(.emptyText(item: 2)))
    #expect(!problems.contains(.emptyText(item: 3)))
    #expect(!problems.contains(.noItems))
  }

  @Test func problems_unknownSize() {
    var document = MossDocument()
    document.description = "A."
    document.items = [item(1)]
    #expect(MossComposer.problems(document, catalog: terms, size: nil) == [.unknownSize])
    #expect(MossComposer.problems(document, catalog: terms, size: PixelSize(width: 1000, height: 640)) == [.unknownSize])
    #expect(MossComposer.problems(document, catalog: terms, size: size).isEmpty)
  }

  @Test(arguments: GoldenTests.names) func goldenThroughTheComposer(name: String) throws {
    let draft = try #require(try JSONSerialization.jsonObject(with: GoldenTests.fixture(name, "draft")) as? [String: Any])
    let size = PixelSize(width: draft["width"] as! Int, height: draft["height"] as! Int)
    let summary = draft["summary"] as! [String: Any]
    var document = MossDocument()
    document.description = summary["caption"] as! String
    document.freeMeta = summary["meta"] as? [String] ?? []
    document.palette = summary["palette"] as? [String] ?? []
    document.canvas = MossCanvas(rawValue: summary["canvas"] as! String)!
    document.items = (draft["items"] as! [[String: Any]]).enumerated().map { index, raw in
      let b = (raw["bbox"] as! [NSNumber]).map(\.doubleValue)
      return MossItem(
        id: index + 1, label: MossLabel(rawValue: raw["label"] as! String)!, caption: raw["caption"] as! String,
        text: raw["text"] as? String ?? "", tags: (raw["tags"] as? [String] ?? []).joined(separator: ", "),
        colors: raw["palette"] as? [String] ?? [],
        box: FracBox(x0: b[0] / Double(size.width), y0: b[1] / Double(size.height), x1: b[2] / Double(size.width), y1: b[3] / Double(size.height)),
        expanded: false)
    }
    let expected = try #require(String(data: GoldenTests.fixture(name, "compiled"), encoding: .utf8)).trimmingCharacters(in: .newlines)
    #expect(MossComposer.json(document, catalog: FakeTerms(meta: [:], caption: [:], negative: []), size: size) == expected)
  }
}
