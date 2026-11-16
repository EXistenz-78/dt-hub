import Foundation
import Testing

@testable import HubCore

@MainActor
struct WorkspaceStateTests {
  let control = WorkspaceTab(id: WorkspaceTab.controlID, title: "Control", systemImage: "photo.on.rectangle")
  let generation = WorkspaceTab(
    id: WorkspaceTab.generationID, title: "Generation", systemImage: "slider.horizontal.3")
  let promptMaster = WorkspaceTab(id: "promptmaster", title: "Prompt Master", systemImage: "text.quote")
  let sphereLight = WorkspaceTab(id: "spherelight", title: "Sphere Light", systemImage: "circle.lefthalf.filled")

  func state(_ defaults: UserDefaults? = nil) -> WorkspaceState {
    WorkspaceState(
      controlTab: control, generationTab: generation,
      defaults: defaults ?? UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!)
  }

  @Test func controlComesBeforeGenerationAndGenerationIsSelectedAtFirst() {
    let state = state()
    #expect(state.tabs == [control, generation])
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func pluginTabsComeFirstInOrder() {
    let state = state()
    state.setPluginTabs([promptMaster, sphereLight])
    #expect(state.tabs == [promptMaster, sphereLight, control, generation])
  }

  @Test func selectsAPluginTab() {
    let state = state()
    state.setPluginTabs([promptMaster])
    state.select(promptMaster.id)
    #expect(state.selectedTabID == promptMaster.id)
  }

  @Test func ignoresSelectionOfUnknownTab() {
    let state = state()
    state.select("missing")
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func fallsBackToGenerationWhenSelectedTabIsRemoved() {
    let state = state()
    state.setPluginTabs([promptMaster, sphereLight])
    state.select(sphereLight.id)
    state.setPluginTabs([promptMaster])
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func keepsSelectionWhenSelectedTabSurvives() {
    let state = state()
    state.setPluginTabs([promptMaster])
    state.select(promptMaster.id)
    state.setPluginTabs([promptMaster, sphereLight])
    #expect(state.selectedTabID == promptMaster.id)
  }

  @Test func pluginCannotReplaceTheBuiltInTabs() {
    let state = state()
    let fakeGeneration = WorkspaceTab(id: WorkspaceTab.generationID, title: "Fake", systemImage: "xmark")
    let fakeControl = WorkspaceTab(id: WorkspaceTab.controlID, title: "Fake", systemImage: "xmark")
    state.setPluginTabs([fakeGeneration, fakeControl, promptMaster])
    #expect(state.tabs == [promptMaster, control, generation])
  }

  @Test func duplicatePluginIDsKeepTheFirst() {
    let state = state()
    let duplicate = WorkspaceTab(id: promptMaster.id, title: "Other", systemImage: "xmark")
    state.setPluginTabs([promptMaster, duplicate])
    #expect(state.tabs == [promptMaster, control, generation])
  }

  @Test func theLastTabUsedOpensAtTheNextLaunch() {
    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
    let first = state(defaults)
    first.select(WorkspaceTab.controlID)
    let second = state(defaults)
    #expect(second.selectedTabID == WorkspaceTab.controlID)
  }

  @Test func aSavedTabThatNoLongerExistsOpensGeneration() {
    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
    defaults.set("promptmaster", forKey: WorkspaceState.selectedTabKey)
    #expect(state(defaults).selectedTabID == WorkspaceTab.generationID)
  }

  @Test func selectNextAndPreviousWalkTheBarAndStopAtTheEnds() {
    let state = state()
    state.setPluginTabs([promptMaster, sphereLight])
    state.select(promptMaster.id)
    state.selectPrevious()
    #expect(state.selectedTabID == promptMaster.id)
    state.selectNext()
    #expect(state.selectedTabID == sphereLight.id)
    state.selectNext()
    #expect(state.selectedTabID == WorkspaceTab.controlID)
    state.selectNext()
    #expect(state.selectedTabID == WorkspaceTab.generationID)
    state.selectNext()
    #expect(state.selectedTabID == WorkspaceTab.generationID)
    state.selectPrevious()
    #expect(state.selectedTabID == WorkspaceTab.controlID)
  }

  @Test func theTabChosenWithTheKeysIsRemembered() {
    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
    let state = state(defaults)
    state.selectPrevious()
    #expect(state.selectedTabID == WorkspaceTab.controlID)
    #expect(defaults.string(forKey: WorkspaceState.selectedTabKey) == WorkspaceTab.controlID)
  }

  // MARK: Tabs in a window of their own

  @Test func detachingTheOpenTabOpensGeneration() {
    let state = state()
    state.setPluginTabs([promptMaster])
    state.select(promptMaster.id)
    state.detach(promptMaster.id)
    #expect(state.isDetached(promptMaster.id))
    #expect(state.tabs.contains(promptMaster))
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func detachingGenerationOpensControlThenTheFirstTabLeft() {
    let state = state()
    state.setPluginTabs([promptMaster])
    state.detach(WorkspaceTab.generationID)
    #expect(state.selectedTabID == WorkspaceTab.controlID)
    state.detach(WorkspaceTab.controlID)
    #expect(state.selectedTabID == promptMaster.id)
    state.detach(promptMaster.id)
    #expect(state.selectedTabID == nil)
  }

  @Test func detachingAnotherTabKeepsTheOpenOne() {
    let state = state()
    state.detach(WorkspaceTab.controlID)
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func aDetachedTabCannotBeSelected() {
    let state = state()
    state.detach(WorkspaceTab.controlID)
    state.select(WorkspaceTab.controlID)
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func attachingOpensTheTab() {
    let state = state()
    state.detach(WorkspaceTab.controlID)
    state.attach(WorkspaceTab.controlID)
    #expect(!state.isDetached(WorkspaceTab.controlID))
    #expect(state.selectedTabID == WorkspaceTab.controlID)
  }

  @Test func nextAndPreviousSkipDetachedTabs() {
    let state = state()
    state.setPluginTabs([promptMaster, sphereLight])   // promptMaster, sphereLight, control, generation
    state.detach(WorkspaceTab.controlID)
    state.selectPrevious()
    #expect(state.selectedTabID == sphereLight.id)
    state.selectNext()
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func nextDoesNothingWhenEveryTabIsDetached() {
    let state = state()
    state.detach(WorkspaceTab.generationID)
    state.detach(WorkspaceTab.controlID)
    state.selectNext()
    #expect(state.selectedTabID == nil)
  }

  @Test func aPluginTabThatGoesIsNoLongerDetached() {
    let state = state()
    state.setPluginTabs([promptMaster])
    state.detach(promptMaster.id)
    state.setPluginTabs([])
    #expect(!state.isDetached(promptMaster.id))
    state.attach(promptMaster.id)   // the window closing afterwards
    #expect(state.selectedTabID == WorkspaceTab.generationID)
  }

  @Test func detachingAnUnknownTabIsIgnored() {
    let state = state()
    state.detach("nope")
    #expect(state.detachedTabIDs.isEmpty)
  }

  @Test func detachingDoesNotChangeTheRememberedTab() {
    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
    let state = state(defaults)
    state.select(WorkspaceTab.controlID)
    state.detach(WorkspaceTab.controlID)
    #expect(defaults.string(forKey: WorkspaceState.selectedTabKey) == WorkspaceTab.controlID)
  }
}
