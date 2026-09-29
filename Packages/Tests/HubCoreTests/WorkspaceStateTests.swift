import Testing

@testable import HubCore

@MainActor
struct WorkspaceStateTests {
  let generation = WorkspaceTab(
    id: WorkspaceTab.generationID, title: "Generation", systemImage: "slider.horizontal.3")
  let promptMaster = WorkspaceTab(id: "promptmaster", title: "Prompt Master", systemImage: "text.quote")
  let sphereLight = WorkspaceTab(id: "spherelight", title: "Sphere Light", systemImage: "circle.lefthalf.filled")

  @Test func startsWithOnlyGenerationSelected() {
    let state = WorkspaceState(generationTab: generation)
    #expect(state.tabs == [generation])
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func pluginTabsFollowGenerationInOrder() {
    let state = WorkspaceState(generationTab: generation)
    state.setPluginTabs([promptMaster, sphereLight])
    #expect(state.tabs == [generation, promptMaster, sphereLight])
  }

  @Test func selectsAPluginTab() {
    let state = WorkspaceState(generationTab: generation)
    state.setPluginTabs([promptMaster])
    state.select(promptMaster.id)
    #expect(state.selectedTabID == promptMaster.id)
  }

  @Test func ignoresSelectionOfUnknownTab() {
    let state = WorkspaceState(generationTab: generation)
    state.select("missing")
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func fallsBackToGenerationWhenSelectedTabIsRemoved() {
    let state = WorkspaceState(generationTab: generation)
    state.setPluginTabs([promptMaster, sphereLight])
    state.select(sphereLight.id)
    state.setPluginTabs([promptMaster])
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func keepsSelectionWhenSelectedTabSurvives() {
    let state = WorkspaceState(generationTab: generation)
    state.setPluginTabs([promptMaster])
    state.select(promptMaster.id)
    state.setPluginTabs([promptMaster, sphereLight])
    #expect(state.selectedTabID == promptMaster.id)
  }

  @Test func pluginCannotReplaceGenerationTab() {
    let state = WorkspaceState(generationTab: generation)
    let impostor = WorkspaceTab(id: WorkspaceTab.generationID, title: "Fake", systemImage: "xmark")
    state.setPluginTabs([impostor, promptMaster])
    #expect(state.tabs == [generation, promptMaster])
  }

  @Test func duplicatePluginIDsKeepTheFirst() {
    let state = WorkspaceState(generationTab: generation)
    let duplicate = WorkspaceTab(id: promptMaster.id, title: "Other", systemImage: "xmark")
    state.setPluginTabs([promptMaster, duplicate])
    #expect(state.tabs == [generation, promptMaster])
  }
}
