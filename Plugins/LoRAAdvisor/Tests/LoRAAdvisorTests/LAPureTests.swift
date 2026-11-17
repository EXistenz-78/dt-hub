import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

struct LALinkTests {
  @Test func civitaiLinks() {
    #expect(LALink.parse("https://civitai.com/models/123456") == .civitai(model: 123456, version: nil))
    let red = LALink.parse("https://civitai.red/models/2958510/event-horizon-or-krealoralab?modelVersionId=3351450")
    #expect(red == .civitai(model: 2_958_510, version: 3_351_450))
    #expect(red?.canonical == "https://civitai.com/models/2958510?modelVersionId=3351450")
    #expect(LALink.parse("  https://www.civitai.com/models/9?foo=1 \n") == .civitai(model: 9, version: nil))
    #expect(LALink.civitai(model: 9, version: nil).canonical == "https://civitai.com/models/9")
  }

  @Test func huggingFaceLinks() {
    let link = LALink.parse("https://huggingface.co/XLabs-AI/flux-RealismLora/tree/main")
    #expect(link == .huggingFace(repo: "XLabs-AI/flux-RealismLora"))
    #expect(link?.canonical == "https://huggingface.co/XLabs-AI/flux-RealismLora")
  }

  @Test(arguments: [
    "http://civitai.com/models/1", "https://civitai.com.evil.io/models/1", "https://user:pw@civitai.com/models/1",
    "https://civitai.com/user/x", "https://civitai.com/models/abc", "https://huggingface.co/solo",
    "https://example.com/models/1", "", "models/1", "https://huggingface.co/models/x",
  ])
  func otherAddressesAreRefused(text: String) {
    #expect(LALink.parse(text) == nil)
  }

  @Test func onlyTheKnownHostsOverHTTPSAreAllowed() {
    for text in ["https://civitai.com/x", "https://blobs-b2.civitai.com/x", "https://us.aws.cdn.hf.co/x", "https://huggingface.co/x"] {
      #expect(LAHosts.isAllowed(URL(string: text)!), "\(text)")
    }
    for text in [
      "http://civitai.com/x", "https://civitai.red/x", "https://evilcivitai.com/x", "https://civitai.com.evil.io/x",
      "https://a:b@civitai.com/x", "file:///etc/passwd", "https://hf.co.evil.io/x",
    ] {
      #expect(!LAHosts.isAllowed(URL(string: text)!), "\(text)")
    }
  }
}

struct LATextTests {
  @Test func htmlBecomesPlainText() {
    #expect(
      LAText.plain(fromHTML: "<p>Hello&nbsp;<b>world</b> &amp; more</p><br><ul><li>one</li><li>two</li></ul>")
        == "Hello world & more one two")
    #expect(LAText.plain(fromHTML: "a<script>alert(1)</script>b<style>p{}</style>c") == "a b c")
    #expect(LAText.plain(fromHTML: "x &lt;b&gt; &#39;y&#39; &quot;z&quot;") == "x <b> 'y' \"z\"")
  }

  @Test func theTextIsCutAtTheLimit() {
    #expect(LAText.plain(fromHTML: String(repeating: "word ", count: 9000)).count == 30000)
  }

  @Test func theFrontMatterGoes() {
    #expect(LAText.withoutFrontMatter("---\na: b\n---\n# Title\ntext") == "# Title\ntext")
    #expect(LAText.withoutFrontMatter("# Title\n---\ntext") == "# Title\n---\ntext")
  }

  @Test func anExcerptEndsAtAWord() {
    let long = String(repeating: "parola ", count: 150)
    let cut = LAText.excerpt(long)
    #expect(cut.count <= 401 && cut.hasSuffix("…") && !cut.hasSuffix(" …"))
    #expect(LAText.excerpt("breve testo") == "breve testo")
    #expect(LAText.firstLine("\n  prima \nseconda") == "prima")
  }
}

struct LANameTests {
  @Test func theQueryIsTheNameOrTheCleanedFile() {
    #expect(LAName.query(name: "Radiance Chrome Voluptuous", file: "x.ckpt") == "Radiance Chrome Voluptuous")
    #expect(LAName.query(name: "", file: "q21_radiancechrome_v1.0_lora_f16.ckpt") == "q21 radiancechrome v1.0")
    #expect(LAName.query(name: " ", file: "analog-film_lora_q8p.ckpt") == "analog film")
  }

  @Test func namesMatchWhateverTheCapitalsThePunctuationAndATrailingVersion() {
    #expect(LAName.matches(lora: "Radiance Chrome Voluptuous v1.0", result: "Radiance Chrome Voluptuous"))
    #expect(LAName.matches(lora: "Radiance Chrome Voluptuous", result: "Radiance Chrome Voluptuous V2"))
    #expect(LAName.matches(lora: "radiance-chrome_voluptuous", result: "Radiance Chrome Voluptuous"))
    #expect(LAName.matches(lora: "Più Luce", result: "piu luce"))
  }

  @Test func aNameThatOnlyLooksAlikeDoesNotMatch() {
    #expect(!LAName.matches(lora: "Radiance", result: "Radiance Chrome Voluptuous"))
    #expect(!LAName.matches(lora: "Kuniyoshi", result: "Utagawa Kuniyoshi [LoRA SDXL]"))
    #expect(!LAName.matches(lora: "", result: ""))
    #expect(!LAName.matches(lora: "v1.0", result: "v2"))
  }
}

struct LACategoryTests {
  @Test func theFiveCategoriesAndUnknowns() {
    for name in ["character", "style", "slider", "edit", "turbo"] { #expect(LACategory(raw: name)?.rawValue == name) }
    #expect(LACategory(raw: "banana") == nil)
    #expect(LACategory(raw: nil) == nil)
    #expect(LACategory.allCases.count == 5)
  }

  @Test func namesInBothLanguages() {
    #expect(LACategory.character.name(italian: true) == "Personaggio")
    #expect(LACategory.character.name(italian: false) == "Character")
    #expect(LACategory.style.name(italian: true) == "Stile")
    #expect(LACategory.style.name(italian: false) == "Style")
    #expect(LACategory.slider.name(italian: true) == "Slider")
    #expect(LACategory.edit.name(italian: false) == "Edit")
    #expect(LACategory.turbo.name(italian: true) == "Turbo")
  }
}

struct LATriggersTests {
  @Test func proposalRules() {
    #expect(LATriggers.proposal(current: "foo style", found: ["Foo Style"]) == nil)
    #expect(LATriggers.proposal(current: "foo style", found: ["foo style,"]) == nil)
    #expect(LATriggers.proposal(current: "", found: ["foo"]) == "foo")
    #expect(LATriggers.proposal(current: "foo", found: ["foo", "bar"]) == "foo, bar")
    #expect(LATriggers.proposal(current: "foo", found: []) == nil)
    #expect(LATriggers.proposal(current: "foo", found: ["bar"]) == "bar")
  }

  @Test func wordsIgnoreCaseAccentsSpacesAndCommas() {
    #expect(LATriggers.words("  Café,, b  a,a ") == ["a", "b", "cafe"])
    #expect(LATriggers.words("") == [])
    #expect(LATriggers.proposal(current: "Café, a", found: ["a  cafe"]) == nil)
  }

  @Test func foundWordsAreKeptAsWrittenWithoutDuplicates() {
    #expect(LATriggers.proposal(current: "", found: ["Foo", "foo", "Bar,"]) == "Foo, Bar")
  }
}

struct LAAnalysisPlanTests {
  let full = LASummary.Analysis(
    summary: "Un riassunto.", category: .turbo, min: 0.6, base: 0.8, max: 1, steps: 8, guidance: 1.5, shift: 3,
    triggers: ["zap"])
  let raw = DTHubCatalogLoRA(file: "a.ckpt", name: "Alpha")

  func make(
    _ analysis: LASummary.Analysis? = nil, lora: DTHubCatalogLoRA? = nil, entry: LAEntry = LAEntry(), replace: Bool = true
  ) -> LAAnalysisPlan {
    LAAnalysisPlan.make(analysis: analysis ?? full, lora: lora ?? raw, entry: entry, replaceNotes: replace)
  }

  @Test func aCompleteAnswerFillsEverything() {
    let plan = make()
    #expect(plan.notes == "Un riassunto.")
    #expect(plan.settings == DTHubLoRASettings(category: .set("turbo"), steps: .set(8), guidance: .set(1.5), shift: .set(3)))
    #expect(plan.weights == LAWeights.Values(min: 0.6, base: 0.8, max: 1))
    #expect(plan.triggerProposal == "zap")
  }

  @Test func aManualCategoryIsNotTouched() {
    var lora = raw
    lora.category = "style"
    let plan = make(lora: lora, entry: LAEntry(categoryManual: true))
    #expect(plan.settings.category == .keep)
    // The final category is the user's (style), so no turbo values.
    #expect(plan.settings.steps == .keep && plan.settings.guidance == .keep && plan.settings.shift == .keep)
  }

  @Test func aManualTurboCategoryStillTakesTheValues() {
    var lora = raw
    lora.category = "turbo"
    let plan = make(lora: lora, entry: LAEntry(categoryManual: true))
    #expect(plan.settings.category == .keep && plan.settings.steps == .set(8))
  }

  @Test func weightsAreWrittenOnlyWhileAllAtDefault() {
    #expect(make(lora: DTHubCatalogLoRA(file: "a", name: "A", minWeight: 0.5)).weights == nil)
    #expect(make(lora: DTHubCatalogLoRA(file: "a", name: "A", weight: 0.7)).weights == nil)
    #expect(make(lora: DTHubCatalogLoRA(file: "a", name: "A", maxWeight: 2)).weights == nil)
    #expect(make(LASummary.Analysis(summary: "x")).weights == nil)
    let onlyMax = make(LASummary.Analysis(max: 1.2))
    #expect(onlyMax.weights == LAWeights.Values(min: nil, base: 1, max: 1.2))
  }

  @Test func manualParamsKeepTheTurboValues() {
    let plan = make(entry: LAEntry(paramsManual: true))
    #expect(plan.settings.category == .set("turbo"))
    #expect(plan.settings.steps == .keep && plan.settings.guidance == .keep && plan.settings.shift == .keep)
  }

  @Test func aCategoryOtherThanTurboKeepsTheTurboValues() {
    var analysis = full
    analysis.category = .style
    let plan = make(analysis)
    #expect(plan.settings.category == .set("style"))
    #expect(plan.settings.steps == .keep && plan.settings.guidance == .keep && plan.settings.shift == .keep)
  }

  @Test func notesFollowTheFlagAndTheSummary() {
    #expect(make(replace: false).notes == nil)
    var empty = full
    empty.summary = nil
    #expect(make(empty).notes == nil)
    empty.summary = ""
    #expect(make(empty).notes == nil)
    var long = full
    long.summary = String(repeating: "a", count: 3000)
    #expect(make(long).notes?.count == 1200)
  }

  @Test func theTriggerIsOnlyProposed() {
    var same = raw
    same.trigger = "ZAP"
    #expect(make(lora: same).triggerProposal == nil)
    #expect(make(lora: same).settings.trigger == .keep && make().settings.trigger == .keep)
    #expect(make(entry: LAEntry(triggerDismissed: "zap")).triggerProposal == nil)
    var none = full
    none.triggers = []
    #expect(make(none).triggerProposal == nil)
  }
}
