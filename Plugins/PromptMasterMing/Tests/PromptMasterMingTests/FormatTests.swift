import Foundation
import Testing

@testable import PromptMasterMing

@Suite("Ming JSON: geometry, export and import")
struct FormatTests {
  @Test func coordinatesAreWrittenAndReadLikeTheNode() throws {
    let box = FracBox(x0: 0.1, y0: 0.05, x1: 0.9, y1: 0.19)
    #expect(MingGeometry.coordinates(box) == "cx: 0.500, cy: 0.120, w: 0.800, h: 0.140")
    let read = try #require(MingGeometry.parse("cx: 0.500, cy: 0.120, w: 0.800, h: 0.140"))
    #expect(abs(read.x0 - 0.1) < 1e-9 && abs(read.y1 - 0.19) < 1e-9)
    #expect(MingGeometry.parse("0.5, 0.5, 0.2, 0.2") != nil)
    #expect(MingGeometry.parse("cx: 1.5, cy: 0.5, w: 0.2, h: 0.2") == nil)
    #expect(MingGeometry.parse("cx: 0.5, cy: 0.5, w: 0, h: 0.2") == nil)
    #expect(MingGeometry.parse("hello") == nil)
    // A box that leaves the canvas is cut at its edge.
    let cut = try #require(MingGeometry.parse("cx: 0.950, cy: 0.500, w: 0.200, h: 0.200"))
    #expect(cut.x1 == 1 && abs(cut.x0 - 0.85) < 1e-9)
  }

  @Test func aspectRatiosAreReducedAndRead() {
    #expect(MingGeometry.aspectRatio(PixelSize(width: 832, height: 1248)) == "2:3")
    #expect(MingGeometry.aspectRatio(PixelSize(width: 1024, height: 1024)) == "1:1")
    #expect(MingGeometry.shape(of: "16:9") == .ratio(16, 9))
    #expect(MingGeometry.shape(of: "portrait, 832 x 1248 px") == .pixels(PixelSize(width: 832, height: 1248)))
    #expect(MingGeometry.shape(of: "1024×1024") == .pixels(PixelSize(width: 1024, height: 1024)))
    #expect(MingGeometry.shape(of: "square") == .ratio(1, 1))
    #expect(MingGeometry.shape(of: "") == nil)
    #expect(MingGeometry.size(for: .ratio(16, 9), keepingLongSideOf: PixelSize(width: 1024, height: 1024)) == PixelSize(width: 1024, height: 576))
    #expect(MingGeometry.size(for: .ratio(2, 3), keepingLongSideOf: nil) == PixelSize(width: 672, height: 1024))
    #expect(MingGeometry.size(for: .pixels(PixelSize(width: 830, height: 1250)), keepingLongSideOf: nil) == PixelSize(width: 832, height: 1248))
  }

  @Test func theExportIsByteForByteTheNodesPrettyJSON() {
    var document = MingDocument()
    document.imageStyle = "modern editorial poster"
    document.ambientLighting = "soft studio lighting"
    document.layers = [
      MingLayer(id: 1, kind: .object, description: "A solid cream background.", text: "", relation: "", colors: [],
                box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1), expanded: false),
      MingLayer(id: 2, kind: .text, description: "condensed white typography", text: "FUTURE MEMORY",
                relation: "Primary headline above the central subject.", colors: ["#FFFFFF"],
                box: FracBox(x0: 0.1, y0: 0.05, x1: 0.9, y1: 0.19), expanded: false),
    ]
    let json = MingComposer.json(document, catalog: MingCatalog(database: Fixture.data.database, config: Fixture.data.config),
                                 size: PixelSize(width: 832, height: 1248))
    #expect(json == Fixture.golden)
  }

  @Test func exactTextIsEscapedOnceAndKeptOutOfTheRelation() {
    var layer = MingLayer(id: 1, kind: .text, description: "", text: "A \"quoted\" \\ line\nbreak", relation: "Under A \"quoted\" \\ line\nbreak",
                          colors: [], box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1), expanded: false)
    #expect(MingComposer.description(of: layer) == "A text element reading exactly \"A \"quoted\" \\ line\nbreak\".")
    #expect(MingComposer.relation(of: layer) == "Under this text element")
    layer.description = "red letters spelling A \"quoted\" \\ line\nbreak!"
    #expect(MingComposer.description(of: layer).hasSuffix(" in red letters spelling the specified text!"))
    #expect(MingJSON.quoted("a\"b\\c\nd\u{1}é") == "\"a\\\"b\\\\c\\nd\\u0001é\"")
  }

  @Test func theNodesPromptRoundTripsUnchanged() throws {
    let imported = try MingImporter.parse(Fixture.golden).get()
    #expect(imported.shape == .ratio(2, 3) && imported.imageStyle == "modern editorial poster")
    #expect(imported.layers.map(\.kind) == [.object, .text])
    #expect(imported.layers[1].text == "FUTURE MEMORY" && imported.layers[1].description == "condensed white typography")
    var document = MingDocument()
    document.imageStyle = imported.imageStyle
    document.ambientLighting = imported.ambientLighting
    document.layers = imported.layers
    let catalog = MingCatalog(database: Fixture.data.database, config: Fixture.data.config)
    #expect(MingComposer.json(document, catalog: catalog, size: PixelSize(width: 832, height: 1248)) == Fixture.golden)
  }

  @Test func aFamilyPromptStyleJSONBecomesLayersWithTheirTexts() throws {
    let imported = try MingImporter.parse("Here it is:\n```json\n" + Fixture.familyStyle + "\n```").get()
    #expect(imported.shape == .pixels(PixelSize(width: 1248, height: 832)))
    #expect(imported.ambientLighting == "bright daylight" && imported.imageStyle == "flat vector poster")
    #expect(imported.layers.count == 3)
    #expect(imported.layers[0].colors == ["#FF8800"] && imported.layers[0].relation == "Base layer.")
    let headline = imported.layers[1]
    #expect(headline.kind == .text && headline.text == "SUMMER SALE" && headline.colors == ["#FFFFFF"])
    #expect(imported.layers[2].kind == .object && imported.layers[2].relation == "" && imported.layers[2].colors == [])
    #expect(imported.warnings.contains { $0.contains("color") })
    // Unchanged, the headline is written as it came; with other words, only the words change.
    #expect(MingComposer.description(of: headline) == "Bold white condensed headline \"SUMMER SALE\" with a soft shadow.")
    var changed = headline
    changed.text = "WINTER SALE"
    #expect(MingComposer.description(of: changed) == "Bold white condensed headline \"WINTER SALE\" with a soft shadow.")
    changed.description = "Bold white condensed letters"
    #expect(MingComposer.description(of: changed) == "A text element reading exactly \"WINTER SALE\" in Bold white condensed letters.")
  }

  @Test func whatIsNotAMingPromptIsRefused() {
    for text in ["", "a cat on a sofa", "{\"layers\": []}", "{\"canvas_settings\": {}, \"layers\": [{\"description\": \"x\"}]}",
                 "{\"canvas_settings\": {}, \"layers\": [{\"description\": \"\", \"coordinates\": \"cx: 0.5, cy: 0.5, w: 1, h: 1\"}]}"] {
      #expect((try? MingImporter.parse(text).get()) == nil, "\(text)")
      #expect(!MingImporter.looksImportable(text))
    }
    #expect(MingImporter.looksImportable(Fixture.golden))
  }

  /// Il JSON scritto a mano dell'utente: la stringa di ambient_lighting chiusa da `”` senza virgola, un colore con un `!`.
  @Test func commonSlipsInAHandWrittenJSONAreRepaired() throws {
    let text = """
      {
        "canvas_settings": {
          "aspect_ratio": "landscape, 1248 x 832 px",
          "ambient_lighting": "moon light is the only light source, it lights the girl from back rsulting in a glowy rim light”
          "image_style": "cinematic film photograph, 35mm lens, shallow depth of field, fine film! grain"
        },
        "layers": [
          {
            "description": "A vast, dark night sky with a faint “milky” band.",
            "coordinates": "cx: 0.500, cy: 0.250, w: 1.000, h: 0.600",
            "hierarchy_and_relation": "The sky is the background.",
            "color_specs": ["#0B1026", "#!1A2540", "#FFFFFF"]
          },
          {
            "description": "A field of red poppies.",
            "coordinates": "cx: 0.500, cy: 0.800, w: 1.000, h: 0.450",
            "hierarchy_and_relation": "The ground."
            "color_specs": ["#8B0000",],
          },
        ]
      }
      """
    let imported = try MingImporter.parse(text).get()
    #expect(imported.ambientLighting.hasSuffix("glowy rim light"))
    #expect(imported.imageStyle.hasPrefix("cinematic film photograph"))
    #expect(imported.shape == .pixels(PixelSize(width: 1248, height: 832)))
    #expect(imported.layers.count == 2)
    #expect(imported.layers[0].description == "A vast, dark night sky with a faint “milky” band.")
    #expect(imported.layers[0].colors == ["#0B1026", "#FFFFFF"])
    #expect(imported.layers[1].colors == ["#8B0000"])
    #expect(imported.warnings.contains { $0.hasPrefix("The JSON had errors that were fixed") })
  }

  @Test func anUnrepairableJSONSaysWhereItBreaks() {
    let text = "{\n  \"canvas_settings\": {\n    \"aspect_ratio\": 2:3\n  },\n  \"layers\": []\n}"
    guard case .failure(let failure) = MingImporter.parse(text) else { Issue.record("parsed"); return }
    #expect(failure.reason.hasPrefix("invalid JSON"))
  }

  @Test func textIsRecognisedOnlyWhenThereIsNoDoubt() {
    #expect(MingText.detectCanonical("A text element reading exactly \"HI\" in red.")! == ("HI", "red"))
    #expect(MingText.detectCanonical("A text element reading exactly \"HI\".")! == ("HI", ""))
    #expect(MingText.detectCanonical("A neon sign reading exactly \"OPEN\" above the door")! == ("OPEN", "A neon sign above the door"))
    #expect(MingText.detectCanonical("A cat") == nil)
    #expect(MingText.detectLoose("Title \"ONE\" and \"TWO\"") == nil)
    #expect(MingText.detectLoose("A red apple called \"FRESH\"") == nil)
    #expect(MingText.detectLoose("Small grey caption \"Made in Italy\" at the bottom") == "Made in Italy")
  }
}
