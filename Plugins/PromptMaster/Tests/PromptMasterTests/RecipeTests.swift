import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@MainActor
@Suite("Recipes")
struct RecipeTests {
  private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pm-recipes-\(UUID().uuidString)") }

  private func state(recipes: URL) -> PMState {
    let state = PMState(
      store: PMStore(defaults: UserDefaults(suiteName: "pm-recipes-\(UUID().uuidString)")!),
      customStore: CustomTermsStore(folder: folder()), recipeStore: RecipeStore(folder: recipes), italian: false)
    state.update(family: "flux2_9b", guide: PMStateTests.guide("flux2_9b"), languageModels: [])
    state.active = true
    return state
  }

  private func recipe(_ name: String, _ terms: [String] = ["fr_closeup"]) -> Recipe {
    Recipe(name: name, selection: terms, mode: .art, booru: false, description: "a cat")
  }

  @Test func aRecipeIsSavedAndComesBackInANewStore() throws {
    let store = RecipeStore(folder: folder())
    #expect(store.load().isEmpty)
    #expect(try store.save(recipe("  Noir  ")) == false)
    #expect(RecipeStore(folder: store.folder).load() == [recipe("Noir")])
  }

  @Test func theSameNameIgnoringCaseReplacesInPlace() throws {
    let store = RecipeStore(folder: folder())
    try store.save(recipe("Noir"))
    try store.save(recipe("Other"))
    #expect(try store.save(recipe("NOIR", ["lq_soft_diffused"])) == true)
    let all = store.load()
    #expect(all.map(\.name) == ["NOIR", "Other"] && all[0].selection == ["lq_soft_diffused"])
  }

  @Test func anEmptyNameIsRefusedAndALongOneIsCut() throws {
    let store = RecipeStore(folder: folder())
    #expect(throws: RecipeStore.Failure.empty) { try store.save(recipe("  \n ")) }
    try store.save(recipe(String(repeating: "a", count: 200)))
    #expect(store.load()[0].name.count == RecipeStore.maxNameLength)
  }

  @Test func deletingRemovesOnlyThatRecipeAndAnUnknownNameChangesNothing() throws {
    let store = RecipeStore(folder: folder())
    try store.save(recipe("One"))
    try store.save(recipe("Two"))
    try store.remove(name: "one")
    try store.remove(name: "nothing")
    #expect(store.load().map(\.name) == ["Two"])
  }

  @Test func anUnreadableFileIsNotOverwritten() throws {
    let dir = folder()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(RecipeStore.fileName)
    try Data("garbage".utf8).write(to: file)
    let store = RecipeStore(folder: dir)
    #expect(store.load().isEmpty)
    #expect(throws: RecipeStore.Failure.unreadableFile) { try store.save(recipe("X")) }
    #expect(try Data(contentsOf: file) == Data("garbage".utf8))
  }

  @Test func theStateSavesLoadsAndDeletes() {
    let dir = folder()
    let state = state(recipes: dir)
    state.setChosen("fr_closeup", true)
    state.mode = .art
    state.description = "a dog"
    #expect(!state.canSaveRecipe)
    state.recipeName = "Dog"
    #expect(state.canSaveRecipe && state.saveRecipe() && state.recipeName.isEmpty)
    state.clearAll(); state.mode = .photo; state.description = "other"
    #expect(state.loadRecipe(named: "dog"))
    #expect(state.selection == ["fr_closeup"] && state.mode == .art && state.description == "a dog")
    // Persisted: a new state on the same folder sees it.
    #expect(self.state(recipes: dir).recipes.map(\.name) == ["Dog"])
    #expect(state.deleteRecipe(named: "Dog") && state.recipes.isEmpty && !state.deleteRecipe(named: "Dog"))
    #expect(self.state(recipes: dir).recipes.isEmpty)
  }

  @Test func savingWithoutANameFailsAndSaysWhy() {
    let state = state(recipes: folder())
    #expect(!state.saveRecipe())
    #expect(state.status == L.text(.recipeNeedsName, italian: false))
  }

  @Test func anEmptyDescriptionInARecipeKeepsTheCurrentOne() throws {
    let dir = folder()
    try RecipeStore(folder: dir).save(Recipe(name: "R", selection: [], mode: .photo, booru: false, description: ""))
    let state = state(recipes: dir)
    state.description = "keep me"
    #expect(state.loadRecipe(named: "R") && state.description == "keep me")
  }

  @Test func theToolsListSaveLoadAndDelete() async throws {
    let state = state(recipes: folder())
    func run(_ tool: String, _ args: [String: Any] = [:]) async -> (String, Bool) {
      let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": args]
      let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
      let answer = await PMTools.handle(call, state: state, actions: .init(write: { nil }, applyRatio: { nil }))
      let o = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
      return (o["text"] as? String ?? "", o["isError"] as? Bool ?? false)
    }
    state.setChosen("fr_closeup", true)
    #expect(await run("save_recipe", ["name": ""]).1)
    #expect(await run("save_recipe", ["name": "A"]).1 == false)
    #expect(await run("list_recipes").0.contains("\"A\""))
    state.clearAll()
    #expect(await run("load_recipe", ["name": "a"]).1 == false && state.selection == ["fr_closeup"])
    #expect(await run("load_recipe", ["name": "nope"]).1)
    #expect(await run("delete_recipe", ["name": "A"]).1 == false)
    #expect(await run("delete_recipe", ["name": "A"]).1)
  }
}
