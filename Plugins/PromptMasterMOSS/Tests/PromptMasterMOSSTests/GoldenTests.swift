import Foundation
import Testing

@testable import PromptMasterMOSS

/// Confronto byte per byte con `compile_prompt.py` di OpenMOSS: ogni `*.draft.json` (pixel dall'angolo) è stato compilato
/// dal compilatore ufficiale in `*.compiled.json`; qui si ricostruisce la stessa uscita con `MossGeometry` e `MossJSON`.
struct GoldenTests {
  static let names = [
    "basic-1024x640", "text-unicode", "full-canvas", "fractional", "minimal", "landscape-1536x1024",
  ]

  static func fixture(_ name: String, _ kind: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "\(name).\(kind)", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// Ricostruisce l'uscita dalla bozza: frazioni = pixel / dimensione, poi `MossGeometry.centered`.
  static func compile(draft: [String: Any]) -> String {
    let size = PixelSize(width: draft["width"] as! Int, height: draft["height"] as! Int)
    let summary = draft["summary"] as! [String: Any]
    func strings(_ any: Any?) -> MossJSON.Value? { (any as? [String]).map { .array($0.map { .string($0) }) } }
    var summaryPairs: [(key: String, value: MossJSON.Value)] = []
    if let meta = strings(summary["meta"]) { summaryPairs.append(("meta", meta)) }
    if let canvas = summary["canvas"] as? String { summaryPairs.append(("canvas", .string(canvas))) }
    if let palette = strings(summary["palette"]) { summaryPairs.append(("palette", palette)) }
    summaryPairs.append(("caption", .string(summary["caption"] as! String)))
    let items: [MossJSON.Value] = (draft["items"] as! [[String: Any]]).map { item in
      var pairs: [(key: String, value: MossJSON.Value)] = [("label", .string(item["label"] as! String)), ("caption", .string(item["caption"] as! String))]
      if let text = item["text"] as? String { pairs.append(("text", .string(text))) }
      let b = (item["bbox"] as! [NSNumber]).map(\.doubleValue)
      let box = FracBox(x0: b[0] / Double(size.width), y0: b[1] / Double(size.height), x1: b[2] / Double(size.width), y1: b[3] / Double(size.height))
      pairs.append(("bbox", .array(MossGeometry.centered(box, in: size).map { .int($0) })))
      if let tags = strings(item["tags"]) { pairs.append(("tags", tags)) }
      if let palette = strings(item["palette"]) { pairs.append(("palette", palette)) }
      return .object(pairs)
    }
    return MossJSON.compact(
      .object([
        ("summary", .object(summaryPairs)), ("items", .array(items)),
        ("bbox_coord_space", .string("abs_centralized")), ("bbox_format", .string("yxyx")),
      ]))
  }

  @Test(arguments: names) func outputEqualsTheOfficialCompiler(name: String) throws {
    let draft = try #require(try JSONSerialization.jsonObject(with: Self.fixture(name, "draft")) as? [String: Any])
    let expected = try #require(String(data: Self.fixture(name, "compiled"), encoding: .utf8)).trimmingCharacters(in: .newlines)
    #expect(Self.compile(draft: draft) == expected)
  }

  @Test func compactSerializationEscapesLikePythonWithoutAscii() {
    let value = MossJSON.Value.object([("t", .string("a\"b\\c\nd\te/f\u{8}\u{c}\u{1}é😀"))])
    #expect(MossJSON.compact(value) == #"{"t":"a\"b\\c\nd\te/f\b\f\u0001é😀"}"#)
  }
}
