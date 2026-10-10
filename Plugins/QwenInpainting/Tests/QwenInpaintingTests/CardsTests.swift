import CoreGraphics
import Testing

@testable import QwenInpainting

@Suite("Cards")
struct CardsTests {
  func mark(_ tool: MarkTool, _ color: MarkColor) -> Mark { Mark(tool: tool, color: color, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)]) }

  @Test func oneCardPerPairOfColourAndTool() {
    #expect(Cards.keys(of: [mark(.box, .green), mark(.sketch, .green)]).map(\.rawValue) == ["green:box", "green:sketch"])
    #expect(Cards.keys(of: [mark(.box, .green), mark(.box, .green)]).map(\.rawValue) == ["green:box"])
    #expect(Cards.keys(of: [mark(.box, .green), mark(.box, .red)]).map(\.rawValue) == ["green:box", "red:box"])
    #expect(
      Cards.keys(of: [mark(.sketch, .red), mark(.box, .green), mark(.sketch, .red)]).map(\.rawValue) == ["red:sketch", "green:box"])
    #expect(Cards.count(of: CardKey(color: .red, tool: .sketch), in: [mark(.sketch, .red), mark(.box, .green), mark(.sketch, .red)]) == 2)
  }

  @Test func titlesAreSingularOrPlural() {
    #expect(Cards.title(CardKey(color: .red, tool: .box), count: 1) == "INSIDE red box")
    #expect(Cards.title(CardKey(color: .red, tool: .box), count: 2) == "INSIDE red boxes")
    #expect(Cards.title(CardKey(color: .blue, tool: .circle), count: 2) == "INSIDE blue circles")
    #expect(Cards.title(CardKey(color: .green, tool: .sketch), count: 2) == "INSIDE green sketches")
    #expect(Cards.title(CardKey(color: .green, tool: .arrow), count: 1) == "WHERE green arrow points")
    #expect(Cards.title(CardKey(color: .green, tool: .arrow), count: 3) == "WHERE green arrows point")
  }

  @Test func sentencesAreCleanedAndEndWithAFullStop() {
    #expect(Cards.sentence(CardKey(color: .red, tool: .box), count: 2, text: "make them blue") == "Inside the red boxes: make them blue.")
    #expect(
      Cards.sentence(CardKey(color: .green, tool: .arrow), count: 1, text: "  add a cat\n here ")
        == "Where the green arrow points: add a cat here.")
    #expect(Cards.sentence(CardKey(color: .red, tool: .circle), count: 1, text: "wow!") == "Inside the red circle: wow!")
    #expect(Cards.sentence(CardKey(color: .red, tool: .circle), count: 1, text: "   ") == nil)
    #expect(Cards.sentence(CardKey(color: .red, tool: .circle), count: 1, text: "") == nil)
    #expect(Cards.sentence(CardKey(color: .red, tool: .sketch), count: 2, text: "x") == "Inside the red sketches: x.")
  }

  @Test func thePromptIsTheSentencesInCardOrderThenTheClosingLine() {
    let marks = [mark(.box, .red), mark(.arrow, .green)]
    let texts = ["red:box": "make it blue", "green:arrow": "add a hat"]
    #expect(
      Cards.prompt(marks: marks, texts: texts)
        == "Inside the red box: make it blue. Where the green arrow points: add a hat. Remove all the colored marks and keep everything else the same.")
    #expect(Cards.prompt(marks: marks, texts: [:]) == "")
    #expect(Cards.prompt(marks: [mark(.box, .red)], texts: ["blue:circle": "ignored"]) == "")
  }

  @Test func theTextOfAHiddenCardIsKeptByItsKey() {
    let texts = ["red:box": "make it blue"]
    #expect(Cards.prompt(marks: [], texts: texts) == "")
    #expect(Cards.prompt(marks: [mark(.box, .red)], texts: texts).hasPrefix("Inside the red box: make it blue."))
  }

  @Test func marksAreClamped() {
    let m = Mark(tool: .sketch, color: .red, width: 200, points: [CGPoint(x: -0.2, y: 1.5)]).clamped()
    #expect(m.points == [CGPoint(x: 0, y: 1)] && m.width == 128)
    #expect(Mark(tool: .box, color: .red, width: 1, points: []).clamped().width == 4)
    let many = Mark(tool: .sketch, color: .red, points: Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 5_000)).clamped()
    #expect(many.points.count == 4_000)
  }

  @Test func theNineColoursAreInTheOrderOfTheSpec() {
    #expect(MarkColor.allCases.map(\.rawValue) == ["yellow", "red", "blue", "cyan", "magenta", "green", "purple", "white", "black"])
    #expect(MarkColor.purple.rgb == (128, 0, 255) && MarkColor.red.rgb == (255, 0, 0))
  }

  @Test func aCardKeyReadsBackFromItsName() {
    #expect(CardKey(rawValue: "red:box") == CardKey(color: .red, tool: .box))
    #expect(CardKey(rawValue: "red") == nil && CardKey(rawValue: "pink:box") == nil)
  }
}
