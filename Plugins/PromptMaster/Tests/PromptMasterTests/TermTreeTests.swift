import Foundation
import Testing

@testable import PromptMaster

@Suite("The list of terms")
struct TermTreeTests {
  private let database = PMData.embeddedDatabase

  private func tree(hidden: Set<String> = [], custom: [CustomTerm] = [], italian: Bool = true) -> TermTree {
    TermTree(database: database, custom: custom, hidden: hidden, italian: italian)
  }

  @Test func theWholeListHasThreeLevelsInTheOrderOfTheDatabase() {
    let tree = tree()
    #expect(tree.groups.map(\.id) == ["A", "B", "C", "D", "E", "F", "G", "H"])
    #expect(tree.groups[0].title == "Camera e ottica")
    #expect(tree.groups[0].categories.first?.id == "framing")
    #expect(tree.groups.flatMap(\.categories).flatMap(\.terms).count == 875)
  }

  @Test func theInterfaceLanguageChoosesTheNames() {
    #expect(tree(italian: false).groups[0].title == "Camera & Optics")
    let framing = tree(italian: false).groups[0].categories[0]
    #expect(framing.title == "Framing" && framing.terms[0].title == "Extreme close-up")
    #expect(framing.details == nil)  // the description is Italian only
    #expect(tree().groups[0].categories[0].details != nil)
    // The language model always gets the English name.
    #expect(tree().groups[0].categories[0].terms[0].english == "Extreme close-up")
  }

  @Test func hiddenCategoriesAreNotThereAndAnEmptyGroupGoesToo() {
    let allOfH = database.categories.filter { $0.group == "H" }.map(\.id)
    let tree = tree(hidden: Set(allOfH + ["framing"]))
    #expect(!tree.groups.contains { $0.id == "H" })
    #expect(!tree.groups[0].categories.contains { $0.id == "framing" })
  }

  @Test func customTermsJoinTheirCategoryAndAreEnglishAsWritten() {
    let custom = [CustomTerm(id: "custom-1", categoryID: "framing", text: "inquadratura dal basso a sinistra")]
    let framing = tree(custom: custom).groups[0].categories[0]
    #expect(framing.terms.last == TermNode(id: "custom-1", title: "inquadratura dal basso a sinistra", english: "inquadratura dal basso a sinistra", isCustom: true))
    // A custom term of a hidden or unknown category is not shown.
    let orphan = [CustomTerm(id: "custom-2", categoryID: "gone", text: "x")]
    #expect(tree(custom: orphan).groups.flatMap(\.categories).flatMap(\.terms).count == 875)
  }

  // MARK: Search

  private func found(_ query: String, italian: Bool = true) -> TermTree {
    tree(italian: italian).filtered(by: query, database: database, italian: italian)
  }

  @Test func aSearchIgnoresCaseAndAccentsAndMatchesBothLanguages() {
    let terms = found("PRIMISSIMO").groups.flatMap(\.categories).flatMap(\.terms).map(\.id)
    #expect(terms.contains("fr_extreme_closeup"))
    #expect(found("extreme close").groups.flatMap(\.categories).flatMap(\.terms).map(\.id).contains("fr_extreme_closeup"))
    #expect(found("intensita").isFiltered)  // "Intensità"-like words match without the accent
  }

  @Test func everyWordOfTheSearchMustMatch() {
    let both = found("primo piano").groups.flatMap(\.categories).flatMap(\.terms)
    #expect(both.contains { $0.id == "fr_closeup" })
    #expect(found("primo zzzz").groups.isEmpty)
  }

  @Test func aCategoryWhoseNameMatchesKeepsAllItsTerms() {
    let framing = found("inquadratura").groups.flatMap(\.categories).first { $0.id == "framing" }
    #expect(framing?.terms.count == database.categories.first { $0.id == "framing" }?.terms.count)
  }

  @Test func aSearchFindsCustomTermsAndAnEmptyOneIsTheWholeList() {
    let custom = [CustomTerm(id: "custom-1", categoryID: "framing", text: "Dal Basso")]
    let narrowed = tree(custom: custom).filtered(by: "basso", database: database, italian: true)
    #expect(narrowed.groups.flatMap(\.categories).flatMap(\.terms).contains { $0.id == "custom-1" })
    let whole = tree().filtered(by: "   ", database: database, italian: true)
    #expect(!whole.isFiltered && whole == tree())
  }

  // MARK: Counts and choices

  @Test func countsOfChosenTermsDoNotChangeWhileOneSearches() {
    let selection: Set<String> = ["fr_closeup", "fr_extreme_closeup", "lq_soft_diffused"]
    let narrowed = found("primo piano")
    #expect(narrowed.chosenCount(inCategory: "framing", selection: selection) == 2)
    #expect(narrowed.chosenCount(inGroup: "A", selection: selection) == 2)
    #expect(tree().chosenCount(inCategory: "nowhere", selection: selection) == 0)
  }

  @Test func theChosenTermsComeInTheOrderOfTheListAndUnknownIdsAreDropped() {
    let tree = tree()
    let ids = tree.selectedTerms(["fr_closeup", "gone", "fr_extreme_closeup"]).map(\.id)
    #expect(ids == ["fr_extreme_closeup", "fr_closeup"])
    #expect(tree.pruned(["fr_closeup", "gone"]) == ["fr_closeup"])
    #expect(tree.selectedTerms(["fr_closeup"])[0].categoryTitle == "Inquadratura")
    #expect(tree.selectedTerms(["fr_closeup"])[0].categoryEnglish == "Framing")
  }

  @Test func termsOfTheNegativeCategoryAreMarkedToAvoid() {
    let negative = database.categories.first { $0.negative == true }!.terms[0].id
    #expect(tree().selectedTerms([negative])[0].isNegative)
    #expect(!tree().selectedTerms(["fr_closeup"])[0].isNegative)
  }
}
