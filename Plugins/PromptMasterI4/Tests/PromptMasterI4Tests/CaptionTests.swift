import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The JSON of the caption")
struct CaptionTests {
  // MARK: The writer

  @Test func theWriterKeepsTheOrderAndWritesOneItemPerLineLikeJSONStringify() {
    let tree = OrderedJSON.object([
      ("b", .int(1)), ("a", .array([.string("x"), .string("y")])), ("empty", .array([])), ("none", .object([])),
    ])
    #expect(
      tree.rendered(indent: 2) == """
        {
          "b": 1,
          "a": [
            "x",
            "y"
          ],
          "empty": [],
          "none": {}
        }
        """)
    #expect(tree.rendered(indent: 1).contains("\n \"b\": 1"))
  }

  @Test func theWriterEscapesWhatJSONNeedsAndNothingElse() {
    #expect(OrderedJSON.quoted("a\"b\\c\nd\re\tf") == #""a\"b\\c\nd\re\tf""#)
    #expect(OrderedJSON.quoted("\u{08}\u{0C}\u{01}\u{1F}") == #""\b\f\u0001\u001f""#)
    #expect(OrderedJSON.quoted("città/☕ \u{2028}") == "\"città/☕ \u{2028}\"")  // no escaping of / or of non-ASCII
  }

  // MARK: The caption

  private func photo() -> I4Caption {
    I4Caption(
      description: "A neon-lit diner at night with a rain-streaked window and a lone customer at the counter",
      aesthetics: "the mood melancholic, a split-complementary scheme, rain falling through the frame",
      lighting: "lit by neon signage, deep, unreadable shadows", style: "framed in a medium shot, shot wide open at f/1.4",
      medium: "shot on expired film", mode: .photo, colors: ["#0B1F3A", "#FF2E63", "#08D9D6"],
      background: "against a rain-soaked city street seen through the diner window",
      elements: [
        .init(type: .obj, bbox: BBox(y0: 320, x0: 120, y1: 900, x1: 560), text: "ignored for an object", desc: "a lone customer hunched over a coffee cup at the counter", colors: ["#F5E6CC"]),
        .init(type: .text, bbox: BBox(y0: 60, x0: 180, y1: 200, x1: 820), text: "OPEN ALL NIGHT", desc: "lettering formed from glowing neon tube, centered above the window", colors: []),
      ])
  }

  /// The example of the old Prompt Master spec §4.3, with the arrays one item per line.
  @Test func thePhotoExampleIsWrittenByteForByte() {
    #expect(
      photo().json == """
        {
          "high_level_description": "A neon-lit diner at night with a rain-streaked window and a lone customer at the counter",
          "style_description": {
            "aesthetics": "the mood melancholic, a split-complementary scheme, rain falling through the frame",
            "lighting": "lit by neon signage, deep, unreadable shadows",
            "photo": "framed in a medium shot, shot wide open at f/1.4",
            "medium": "shot on expired film",
            "color_palette": [
              "#0B1F3A",
              "#FF2E63",
              "#08D9D6"
            ]
          },
          "compositional_deconstruction": {
            "background": "against a rain-soaked city street seen through the diner window",
            "elements": [
              {
                "type": "obj",
                "bbox": [
                  320,
                  120,
                  900,
                  560
                ],
                "desc": "a lone customer hunched over a coffee cup at the counter",
                "color_palette": [
                  "#F5E6CC"
                ]
              },
              {
                "type": "text",
                "bbox": [
                  60,
                  180,
                  200,
                  820
                ],
                "text": "OPEN ALL NIGHT",
                "desc": "lettering formed from glowing neon tube, centered above the window"
              }
            ]
          }
        }
        """)
  }

  @Test func inArtModeArtStyleComesAfterMediumAndPhotoIsAbsent() throws {
    var caption = photo()
    caption.mode = .art
    caption.style = "Symbolism, by Gustav Klimt"
    caption.medium = "oil on canvas"
    caption.colors = []
    let json = caption.json
    func position(_ key: String) throws -> String.Index { try #require(json.range(of: "\"\(key)\"")?.lowerBound) }
    #expect(try position("aesthetics") < position("lighting") && position("lighting") < position("medium"))
    #expect(try position("medium") < position("art_style") && position("art_style") < position("color_palette"))
    #expect(!json.contains("\"photo\""))
    #expect(json.contains("\"color_palette\": [],\n") || json.contains("\"color_palette\": []\n"))
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let style = try #require(object["style_description"] as? [String: Any])
    #expect(style["art_style"] as? String == "Symbolism, by Gustav Klimt" && style["color_palette"] as? [String] == [])
  }

  @Test func inPhotoModePhotoComesBeforeMediumAndArtStyleIsAbsent() throws {
    let json = photo().json
    #expect(try #require(json.range(of: "\"photo\"")).lowerBound < #require(json.range(of: "\"medium\"")).lowerBound)
    #expect(!json.contains("art_style"))
  }

  @Test func anElementHasItsKeysInTheOrderTypeBboxTextDescPaletteAndOnlyWhatItHas() throws {
    var caption = photo()
    caption.elements = [
      .init(type: .text, bbox: nil, text: "HI", desc: "d", colors: ["#000000"]),
      .init(type: .obj, bbox: nil, text: "x", desc: "", colors: []),
    ]
    let json = caption.json
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let elements = try #require((object["compositional_deconstruction"] as? [String: Any])?["elements"] as? [[String: Any]])
    #expect(Set(elements[0].keys) == ["type", "text", "desc", "color_palette"])  // no box: no bbox
    #expect(Set(elements[1].keys) == ["type", "desc"] && elements[1]["desc"] as? String == "")  // an object has no text, no palette
    let first = try #require(json.range(of: "\"type\": \"text\"")?.lowerBound)
    let text = try #require(json.range(of: "\"text\": \"HI\"")?.lowerBound)
    let desc = try #require(json.range(of: "\"desc\": \"d\"")?.lowerBound)
    let palette = try #require(json.range(of: "\"color_palette\": [\n          \"#000000\"")?.lowerBound)
    #expect(first < text && text < desc && desc < palette)
  }

  @Test func theTextOfALetteringGoesOutAsItWasWrittenWithQuotesSlashesAndAccents() throws {
    var caption = photo()
    caption.elements = [.init(type: .text, bbox: nil, text: "Caffè \"Roma\" 24/7 \\ ☕", desc: "", colors: [])]
    let object = try #require(JSONSerialization.jsonObject(with: Data(caption.json.utf8)) as? [String: Any])
    let elements = try #require((object["compositional_deconstruction"] as? [String: Any])?["elements"] as? [[String: Any]])
    #expect(elements[0]["text"] as? String == "Caffè \"Roma\" 24/7 \\ ☕")
    #expect(caption.json.contains("24/7") && !caption.json.contains("\\/"))
  }

  @Test func theRootAlwaysHasItsThreeKeysInOrderEvenWhenEmpty() throws {
    let empty = I4Caption(description: "", aesthetics: "", lighting: "", style: "", medium: "", mode: .photo, colors: [], background: "", elements: [])
    let json = empty.json
    let keys = ["high_level_description", "style_description", "compositional_deconstruction"]
    let places = try keys.map { try #require(json.range(of: "\"\($0)\"")).lowerBound }
    #expect(places == places.sorted())
    #expect(json.contains("\"elements\": []") && !json.contains("aspect_ratio"))
  }
}
