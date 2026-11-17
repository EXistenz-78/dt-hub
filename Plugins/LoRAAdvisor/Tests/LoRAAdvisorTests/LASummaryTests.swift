import Foundation
import Testing

@testable import LoRAAdvisor

@Suite struct LASummaryTests {
  @Test func parsesCleanJSON() {
    let a = LASummary.parse(
      #"{"summary":"Un LoRA.","category":"style","weight":{"min":0.6,"base":0.8,"max":1.0},"turbo":{"steps":8,"guidance":1.5,"shift":3},"triggers":["foo","bar"]}"#)
    #expect(a?.summary == "Un LoRA.")
    #expect(a?.category == .style)
    #expect(a?.min == 0.6 && a?.base == 0.8 && a?.max == 1.0)
    #expect(a?.steps == 8 && a?.guidance == 1.5 && a?.shift == 3)
    #expect(a?.triggers == ["foo", "bar"])
  }

  @Test func parsesInsideFencesAndAroundText() {
    let fenced = "```json\n{\"summary\":\"Ok\",\"category\":\"edit\"}\n```"
    #expect(LASummary.parse(fenced)?.category == .edit)
    let around = "Ecco: {\"summary\":\"Ok\",\"category\":\"turbo\"} fatto."
    #expect(LASummary.parse(around)?.category == .turbo)
  }

  @Test func acceptsNumbersAsStrings() {
    let a = LASummary.parse(#"{"weight":{"min":"0.5","base":"0.8","max":"1"},"turbo":{"steps":"8","guidance":"2","shift":"3.5"}}"#)
    #expect(a?.min == 0.5 && a?.base == 0.8 && a?.max == 1)
    #expect(a?.steps == 8 && a?.guidance == 2 && a?.shift == 3.5)
  }

  @Test func bringsNumbersIntoRange() {
    let swapped = LASummary.parse(#"{"weight":{"min":1.2,"base":0.8,"max":0.4}}"#)
    #expect(swapped?.min == 0.4 && swapped?.max == 0.4)
    #expect(swapped?.base == 0.4)
    let big = LASummary.parse(#"{"weight":{"base":9},"turbo":{"steps":900,"guidance":1e9,"shift":-3}}"#)
    #expect(big?.base == 4)
    #expect(big?.steps == 200 && big?.guidance == 50 && big?.shift == 0)
    #expect(LASummary.parse(#"{"turbo":{"steps":0}}"#)?.steps == 1)
  }

  @Test func tolerantOfWrongFields() {
    let a = LASummary.parse(#"{"summary":"  ","category":"banana","weight":"heavy","turbo":{"steps":null,"guidance":"abc"},"triggers":"foo"}"#)
    #expect(a != nil)
    #expect(a?.summary == nil && a?.category == nil)
    #expect(a?.min == nil && a?.base == nil && a?.max == nil)
    #expect(a?.steps == nil && a?.guidance == nil && a?.shift == nil)
    #expect(a?.triggers == [])
    #expect(LASummary.parse(#"{"category":"none"}"#)?.category == nil)
    #expect(LASummary.parse(#"{"triggers":["a",3,"  ","b"]}"#)?.triggers == ["a", "b"])
  }

  @Test func noJSONGivesNil() {
    #expect(LASummary.parse("Un riassunto semplice.") == nil)
    #expect(LASummary.parse("{ non valido") == nil)
    #expect(LASummary.parse("") == nil)
  }

  @Test func promptKeepsTheStartOfThePage() {
    let page = String(repeating: "a", count: 100_000)
    let prompt = LASummary.prompt(pageText: page)
    #expect(prompt.count <= LASummary.pageBudget + "<page>\n\n</page>".count)
    #expect(prompt.hasPrefix("<page>\n") && prompt.hasSuffix("\n</page>"))
    #expect(LASummary.prompt(pageText: "short") == "<page>\nshort\n</page>")
  }

  @Test func systemAsksForJSONOnly() {
    for italian in [true, false] {
      let s = LASummary.system(italian: italian)
      for word in ["JSON", "character", "style", "slider", "edit", "turbo", "none", "triggers", "weight", "<page>"] {
        #expect(s.contains(word))
      }
    }
  }
}
