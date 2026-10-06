import Foundation
import Testing

@testable import PromptMasterI4

@Suite("What the user chooses and writes")
struct DocumentTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  // MARK: One term per category

  @Test func choosingATermReplacesTheOtherOneOfTheSameCategoryAndChoosingItAgainTakesItAway() {
    var document = I4Document()
    document.choose("fr_closeup", catalog: catalog)
    document.choose("fr_wide", catalog: catalog)  // same category: Framing
    #expect(document.selection == ["fr_wide"])
    document.choose("ca_low_angle", catalog: catalog)  // another category of the same section
    #expect(document.selection == ["fr_wide", "ca_low_angle"])
    document.choose("fr_wide", catalog: catalog)
    #expect(document.selection == ["ca_low_angle"])
  }

  @Test func aSectionCanHaveOneTermInEachOfItsCategories() {
    var document = I4Document()
    for id in ["moodt_moody", "mo_peaceful", "at_dreamy", "ch_analogous"] { document.choose(id, catalog: catalog) }
    // moodt_moody and mo_peaceful are both in the merged Mood: only the last stays.
    #expect(document.selection == ["mo_peaceful", "at_dreamy", "ch_analogous"])
    #expect(document.chosenCount(in: .aesthetics, catalog: catalog) == 3)
  }

  @Test func mediumTakesOneTermInAllItsCategoriesAndSoDoesTheBackdrop() {
    var document = I4Document()
    document.choose("md_3d_render", catalog: catalog)  // Digital & 3D
    document.choose("fs_portra400", catalog: catalog)  // Film stock: another category of Medium
    #expect(document.selection == ["fs_portra400"])
    document.choose("bg_white", catalog: catalog)
    document.choose("bg_gradient", catalog: catalog)
    #expect(document.selection == ["fs_portra400", "bg_gradient"])
  }

  @Test func unknownTermsAndTermsTheModeDoesNotShowAreIgnored() {
    var document = I4Document()
    document.choose("nothing", catalog: catalog)
    document.choose("am_cubism", catalog: catalog)  // an art movement, in Photo mode
    document.choose("ofx_bloom", catalog: catalog)  // Optical FX is Photo only…
    #expect(document.selection == ["ofx_bloom"])
    document.mode = .art
    document.choose("fr_closeup", catalog: catalog)  // …and Framing is Photo only
    #expect(document.selection == ["ofx_bloom"])
    document.choose("ty_bold_sans", catalog: catalog)  // the lettering menu is not a list
    #expect(document.selection == ["ofx_bloom"])
  }

  // MARK: Photo ↔ Art

  @Test func changingModeDropsTheChoicesOfTheCategoriesThatDisappearAndKeepsTheCommonOnes() {
    var document = I4Document()
    for id in ["fr_closeup", "ofx_bloom", "lq_soft", "mo_peaceful", "md_3d_render", "fs_portra400", "bg_white"] {
      document.choose(id, catalog: catalog)
    }
    #expect(document.selection == ["fr_closeup", "ofx_bloom", "lq_soft", "mo_peaceful", "fs_portra400", "bg_white"])  // Digital 3D was replaced
    document.setMode(.art, catalog: catalog)
    #expect(document.mode == .art && document.selection == ["lq_soft", "mo_peaceful", "bg_white"])
    document.choose("am_cubism", catalog: catalog)
    document.choose("md_3d_render", catalog: catalog)  // shared by both modes
    document.setMode(.photo, catalog: catalog)
    #expect(document.selection == ["lq_soft", "mo_peaceful", "bg_white", "md_3d_render"])
  }

  // MARK: The raw texts

  @Test func theRawTextOfAFieldIsTheEnglishNamesInTheOrderOfTheCategories() {
    var document = I4Document()
    document.choose("lq_soft", catalog: catalog)  // Light Quality
    document.choose("ls_neon", catalog: catalog)  // Light Source comes first
    #expect(document.rawText(.lighting, catalog: catalog) == "Neon lighting, Soft light")
    #expect(document.rawText(.medium, catalog: catalog) == "")
  }

  @Test func theBackdropIsTheUsersWordsThenTheChosenTermAndTheDescriptionIsTrimmed() {
    var document = I4Document()
    document.background = "  a wet street  "
    document.choose("bg_blurred", catalog: catalog)
    #expect(document.rawBackground(catalog: catalog) == "a wet street, blurred background")
    document.background = ""
    #expect(document.rawBackground(catalog: catalog) == "blurred background")
    document.description = "  a diner \n"
    #expect(document.caption(catalog: catalog).description == "a diner")
  }

  @Test func aTextElementGetsItsLetteringTermAfterItsDescriptionAndAnObjectDoesNot() {
    var document = I4Document()
    let text = document.addElement(type: .text)
    let object = document.addElement()
    for id in [text, object] {
      document.updateElement(id) {
        $0.desc = "above the door"
        $0.lettering = "ty_neon_sign"
        $0.text = "BAR"
      }
    }
    let captionElements = document.caption(catalog: catalog).elements
    #expect(captionElements[0].desc == "above the door, neon sign lettering" && captionElements[0].text == "BAR")
    #expect(captionElements[1].desc == "above the door")
    #expect(document.elements[0].rawDescription(catalog: catalog) == captionElements[0].desc)
  }

  @Test func theCaptionOfADocumentFollowsTheModeAndUsesTheRawTexts() {
    var document = I4Document()
    document.description = "two friends"
    document.choose("ls_starlight", catalog: catalog)
    document.choose("fr_closeup", catalog: catalog)
    let photo = document.caption(catalog: catalog)
    #expect(photo.lighting == "Starlight" && photo.style == "Close-up" && photo.mode == .photo)
    #expect(photo.json.contains("\"photo\": \"Close-up\""))
    document.setMode(.art, catalog: catalog)
    #expect(document.caption(catalog: catalog).style == "" && document.caption(catalog: catalog).json.contains("\"art_style\": \"\""))
  }

  // MARK: The palette

  @Test func theStylePaletteHasAtMost16CapitalHexColors() {
    var document = I4Document()
    document.addColor("#ab12cd")
    document.addColor("nonsense")
    document.addColor("00ff7f")
    #expect(document.colors == ["#AB12CD", "#00FF7F"])
    for _ in 0..<30 { document.addColor("#123456") }
    #expect(document.colors.count == 16 && !document.canAddColor)
  }

  @Test func anElementsPaletteHasAtMostFiveColors() {
    var document = I4Document()
    let id = document.addElement()
    for _ in 0..<9 { document.addElementColor(id, "#FFFFFF") }
    #expect(document.elements[0].colors.count == 5)
  }

  @Test func randomColorsAreCapitalSixDigitHex() {
    var generator = SeededGenerator(seed: 7)
    for _ in 0..<50 {
      let hex = Palette.random(using: &generator)
      #expect(Palette.normalize(hex) == hex && hex.count == 7)
    }
    #expect(Palette.hex(red: 1, green: 0.5, blue: 0) == "#FF8000")
    let parts = Palette.components("#FF8000")
    #expect(parts?.red == 1 && abs((parts?.green ?? 0) - 0.5) < 0.01 && parts?.blue == 0)
    #expect(Palette.components("zzz") == nil)
  }

  // MARK: The elements

  @Test func elementsKeepTheirOrderAndCanMoveUpAndDownButNotOffTheEnds() {
    var document = I4Document()
    let (a, b, c) = (document.addElement(), document.addElement(), document.addElement())
    #expect(a == 1 && b == 2 && c == 3)
    document.moveElement(c, by: -1)
    #expect(document.elements.map(\.id) == [1, 3, 2])
    document.moveElement(a, by: -1)
    document.moveElement(b, by: 1)
    #expect(document.elements.map(\.id) == [1, 3, 2])
    document.removeElement(3)
    #expect(document.elements.map(\.id) == [1, 2] && document.addElement() == 4)  // ids are never reused
  }

  @Test func changingTheTypeKeepsTheTextAndTheDescription() {
    var document = I4Document()
    let id = document.addElement()
    document.updateElement(id) {
      $0.desc = "d"
      $0.text = "t"
      $0.type = .text
    }
    document.updateElement(id) { $0.type = .obj }
    #expect(document.elements[0].desc == "d" && document.elements[0].text == "t")
    #expect(document.caption(catalog: catalog).json.contains("\"text\"") == false)
  }

  // MARK: The boxes

  @Test func aBoxIsPutInOrderInsideTheGridAndNeedsSidesOfAtLeast20() {
    #expect(BBox.normalized(y0: 500, x0: 900, y1: 100, x1: 100) == BBox(y0: 100, x0: 100, y1: 500, x1: 900))
    #expect(BBox.normalized(y0: -50, x0: 0, y1: 2000, x1: 1000) == BBox(y0: 0, x0: 0, y1: 1000, x1: 1000))
    #expect(BBox.normalized(y0: 0, x0: 0, y1: 19, x1: 500) == nil && BBox.normalized(y0: 0, x0: 0, y1: 20, x1: 20) != nil)
  }

  @Test func aBoxIsReadFromFourNumbersWrittenInAnyCommonWay() {
    let box = BBox(y0: 10, x0: 20, y1: 300, x1: 400)
    for text in ["10, 20, 300, 400", "[10,20,300,400]", " 10 20 300 400 "] { #expect(BBox.parse(text) == box, "\(text)") }
    #expect(BBox.parse("1, 2, 3") == nil && BBox.parse("a b c d") == nil && BBox.parse("") == nil && BBox.parse("1 2 3 4 5") == nil)
    #expect(BBox.parse("0 0 5 500") == nil)  // too thin
    #expect(box.text == "[10, 20, 300, 400]" && box.array == [10, 20, 300, 400])
  }

  @Test func aPositionIsKeptAsSoonAsItIsReadableAndAnUnreadableTextChangesNothing() {
    let box = BBox(y0: 10, x0: 20, y1: 300, x1: 400)
    #expect(BBox.resolve("10, 20, 300, 400", current: nil) == box)
    #expect(BBox.resolve("", current: box) == nil && BBox.resolve("  ", current: box) == nil)  // emptied: no position
    #expect(BBox.resolve("10, 20, 3", current: box) == box)  // half typed: the old box stays
    #expect(BBox.resolve("0 0 5 500", current: box) == box && BBox.resolve("a b c d", current: nil) == nil)
  }

  @Test func colorsAreChangedAndRemovedOnlyWhenTheirIndexStillExists() {
    var document = I4Document()
    document.colors = ["#111111", "#222222"]
    let id = document.addElement()
    document.updateElement(id) { $0.colors = ["#333333"] }
    document.setColor(at: 1, to: "#abcdef")
    document.setColor(at: 7, to: "#000000")  // gone: no trap, no change
    document.setColor(at: 0, to: "nonsense")
    #expect(document.colors == ["#111111", "#ABCDEF"])
    document.removeColor(at: 9)
    document.removeColor(at: -1)
    #expect(document.colors.count == 2)
    document.removeColor(at: 0)
    #expect(document.colors == ["#ABCDEF"])
    document.setElementColor(id, at: 0, to: "#ffffff")
    document.setElementColor(id, at: 4, to: "#000000")
    document.setElementColor(999, at: 0, to: "#000000")
    #expect(document.elements[0].colors == ["#FFFFFF"])
    document.removeElementColor(id, at: 3)
    document.removeElementColor(999, at: 0)
    #expect(document.elements[0].colors == ["#FFFFFF"])
    document.removeElementColor(id, at: 0)
    #expect(document.elements[0].colors.isEmpty)
  }

  // MARK: Persistence of the document itself

  @Test func decimalsInAPositionAreRoundedAndNotSplitIntoSeparateNumbers() {
    #expect(BBox.parse("100.5, 100, 600, 600") == BBox(y0: 101, x0: 100, y1: 600, x1: 600))
    #expect(BBox.parse("10,5 20 300 400") == nil)  // a decimal comma is a separator: five numbers
    #expect(BBox.parse("1.2.3 4 5 6") == nil)
    #expect(BBox.parse("-5, 0, 300, 400") == BBox(y0: 0, x0: 0, y1: 300, x1: 400))  // clamped into the grid
  }

  @Test func textThatIsNeitherEmptyNorAPositionIsUnreadable() {
    #expect(!BBox.isUnreadable("") && !BBox.isUnreadable("   ") && !BBox.isUnreadable("100, 100, 600, 600"))
    #expect(BBox.isUnreadable("100, 100, 110, 110") && BBox.isUnreadable("1, 2, 3") && BBox.isUnreadable("abc"))
  }

  @Test func aDocumentSurvivesBeingEncodedAndDecoded() throws {
    var document = I4Document()
    document.description = "x"
    document.choose("ls_neon", catalog: catalog)
    document.addColor("#112233")
    let id = document.addElement(type: .text, bbox: BBox(y0: 0, x0: 0, y1: 100, x1: 100))
    document.updateElement(id) { $0.text = "HI" }
    let back = try JSONDecoder().decode(I4Document.self, from: JSONEncoder().encode(document))
    #expect(back == document)
  }
}

/// A random number generator that always gives the same numbers for the same seed (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
