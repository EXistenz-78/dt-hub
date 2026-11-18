import Foundation
import HubKit
import Testing

@testable import HubCore

/// Grouping of LoRAs into picker sections by category, and the search filter.
struct LoRAPickerSectionsTests {
  private func lora(_ name: String, trigger: String = "", category: String? = nil) -> CatalogLoRA {
    CatalogLoRA(file: "\(name).ckpt", name: name, family: nil, trigger: trigger, category: category)
  }

  private func names(_ section: LoRAPickerSections.Section) -> [String] { section.loras.map(\.name) }

  @Test func theOrderMatchesTheKnownCategories() {
    #expect(Set(LoRAPickerSections.order) == LoRAOverrides.categories)
  }

  @Test func sectionsFollowTheFixedOrder() {
    let loras = [
      lora("a", category: "turbo"), lora("b", category: "edit"), lora("c"),
      lora("d", category: "slider"), lora("e", category: "style"), lora("f", category: "character"),
    ]
    let sections = LoRAPickerSections.make(loras: loras, query: "")
    #expect(sections.map(\.category) == ["character", "style", "slider", "edit", "turbo", nil])
  }

  @Test func loRAsInASectionAreSortedByName() throws {
    let loras = [lora("Item 10", category: "style"), lora("item 2", category: "style"), lora("Alpha", category: "style")]
    let sections = LoRAPickerSections.make(loras: loras, query: "")
    let first = try #require(sections.first)
    #expect(names(first) == ["Alpha", "item 2", "Item 10"])
  }

  @Test func aMissingOrUnknownCategoryGoesToNoCategory() throws {
    let loras = [lora("a"), lora("b", category: "weird"), lora("c", category: "style")]
    let sections = LoRAPickerSections.make(loras: loras, query: "")
    #expect(sections.map(\.category) == ["style", nil])
    let last = try #require(sections.last)
    #expect(names(last) == ["a", "b"])
  }

  @Test func emptySectionsAreOmitted() {
    let sections = LoRAPickerSections.make(loras: [lora("a", category: "edit")], query: "")
    #expect(sections.map(\.category) == ["edit"])
  }

  @Test func queryMatchesNameAndTriggerIgnoringCaseAccentsAndEdgeSpaces() {
    let loras = [lora("Café Look", trigger: "zzz"), lora("Plain", trigger: "Éclair")]
    #expect(LoRAPickerSections.make(loras: loras, query: "  CAFE ").flatMap(\.loras).map(\.name) == ["Café Look"])
    #expect(LoRAPickerSections.make(loras: loras, query: "\neclair\n").flatMap(\.loras).map(\.name) == ["Plain"])
  }

  @Test func queryFiltersEverySection() {
    let loras = [lora("moon a", category: "style"), lora("sun", category: "style"), lora("moon b"), lora("x", category: "edit")]
    let sections = LoRAPickerSections.make(loras: loras, query: "moon")
    #expect(sections.map(\.category) == ["style", nil])
    #expect(sections.flatMap(\.loras).map(\.name) == ["moon a", "moon b"])
  }

  @Test func aQueryWithNoResultIsEmpty() {
    #expect(LoRAPickerSections.make(loras: [lora("a")], query: "nothing").isEmpty)
  }

  @Test func anEmptyQueryKeepsEverything() {
    let loras = [lora("a", category: "style"), lora("b")]
    #expect(LoRAPickerSections.make(loras: loras, query: "").flatMap(\.loras).count == 2)
    #expect(LoRAPickerSections.make(loras: loras, query: "  \n ").flatMap(\.loras).count == 2)
  }
}
