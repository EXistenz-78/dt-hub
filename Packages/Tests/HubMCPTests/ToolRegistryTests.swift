import MCP
import Testing

@testable import HubMCP

@MainActor
struct ToolRegistryTests {
  func names(_ h: Harness) -> Set<String> { Set(h.registry.visibleTools().map(\.name)) }

  func extra(_ name: String, _ level: ToolLevel, specialist: Bool = false) -> ToolSpec {
    ToolSpec(name: name, description: name, level: level, requiresSpecialist: specialist) { _, _ in [.text("ok")] }
  }

  @Test func readOnlyModeListsOnlyReadTools() {
    let h = Harness(mode: .readOnly, extraSpecs: [extra("e", .edit), extra("c", .control)])
    #expect(names(h).contains("get_app_state"))
    #expect(!names(h).contains("e") && !names(h).contains("c"))
  }

  @Test func editModeAddsEditTools() {
    let h = Harness(mode: .editFields, extraSpecs: [extra("e", .edit), extra("c", .control)])
    #expect(names(h).contains("e") && !names(h).contains("c"))
  }

  @Test func fullModeAddsControlTools() {
    let h = Harness(mode: .full, extraSpecs: [extra("e", .edit), extra("c", .control)])
    #expect(names(h).contains("e") && names(h).contains("c"))
  }

  @Test func callingHiddenToolSaysNotAvailableInThisMode() async {
    let h = Harness(mode: .readOnly, extraSpecs: [extra("c", .control)])
    let result = await h.registry.call("c", arguments: [:])
    #expect(result.isError)
    guard case .text(let text) = result.outputs.first else { Issue.record("no text"); return }
    #expect(text.contains("not available") && text.contains("readOnly"))
  }

  @Test func unknownToolIsAnError() async {
    let result = await Harness().registry.call("nope", arguments: [:])
    #expect(result.isError)
  }

  @Test func specialistToolsHiddenWhenHostHasNoSpecialist() {
    let h = Harness(mode: .full, extraSpecs: [extra("enhance_prompt", .control, specialist: true)])
    h.host.hasSpecialistLLM = false
    #expect(!names(h).contains("enhance_prompt"))
  }

  @Test func specialistToolsShownWhenHostHasSpecialist() {
    let h = Harness(mode: .full, extraSpecs: [extra("enhance_prompt", .control, specialist: true)])
    h.host.hasSpecialistLLM = true
    #expect(names(h).contains("enhance_prompt"))
  }

  @Test func hostDidChangeFiresListChangedWhenSpecialistAvailabilityChanges() {
    let h = Harness(mode: .full, extraSpecs: [extra("enhance_prompt", .control, specialist: true)])
    var fired = 0
    h.registry.onListChanged = { fired += 1 }
    h.registry.hostDidChange()
    #expect(fired == 0)
    h.host.hasSpecialistLLM = true
    h.registry.hostDidChange()
    #expect(fired == 1)
    h.registry.hostDidChange()
    #expect(fired == 1)
  }

  @Test func modeChangeFiresListChanged() {
    let h = Harness(mode: .readOnly, extraSpecs: [extra("e", .edit)])
    var fired = 0
    h.registry.onListChanged = { fired += 1 }
    h.settings.value.mode = .editFields
    h.registry.hostDidChange()
    #expect(fired == 1)
  }

  @Test func everyToolHasAnnotationsMatchingItsLevel() {
    let h = Harness(mode: .full, extraSpecs: [extra("e", .edit), extra("c", .control)])
    for spec in h.registry.visibleTools() {
      #expect(spec.tool.annotations.readOnlyHint == (spec.level == .read), "\(spec.name)")
      #expect(spec.tool.annotations.destructiveHint == false)
    }
  }
}
