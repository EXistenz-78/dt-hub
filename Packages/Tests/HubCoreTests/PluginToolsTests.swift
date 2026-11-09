import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginToolsTests {
  let root = PluginFixture.folder()

  func registry(loader: FakeLoader, enabled: Set<String> = ["a"]) -> PluginRegistry {
    let settings = PluginSettingsStore(fileURL: root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json"))
    settings.save(enabled)
    return PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
  }

  func loaded(tools: [PluginToolDeclaration], families: [String]? = nil) throws -> (PluginRegistry, FakeLoader) {
    try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
    let loader = FakeLoader()
    loader.tools["a"] = tools
    loader.families["a"] = families
    let registry = registry(loader: loader)
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters())
    return (registry, loader)
  }

  let list = PluginToolDeclaration(name: "list_things", description: "Lists", level: .read)

  @Test func manifestWithToolsRoundTripsAndDropsBadDeclarations() throws {
    let json = """
      {"id":"a","name":"A","contract":1,"tools":[
        {"name":"ok_tool","description":"d","level":"edit","parameters":[{"name":"x","type":"number","description":"n","required":true},{"name":"Bad Name","type":"string"}]},
        {"name":"Bad-Name","description":"d","level":"read"},
        {"name":"no_level","description":"d"},
        {"name":"gen","description":"d","level":"generate","timeout":9999}]}
      """
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    #expect(manifest.tools?.map(\.name) == ["ok_tool", "gen"])
    #expect(manifest.tools?[0].parameters.map(\.name) == ["x"])
    #expect(manifest.tools?[1].effectiveTimeout == .seconds(600))
    let again = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(manifest))
    #expect(again == manifest)
  }

  @Test func aManifestWithoutToolsHasNone() throws {
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(#"{"id":"a","name":"A","contract":1}"#.utf8))
    #expect(manifest.tools == nil)
  }

  @Test func theToolCallMessageCarriesTheArguments() throws {
    let message = PluginToolCall(tool: "advise", arguments: Data(#"{"goal":"film look"}"#.utf8)).message()
    let object = try #require(try JSONSerialization.jsonObject(with: message) as? [String: Any])
    #expect(object["type"] as? String == "tool.call" && object["tool"] as? String == "advise")
    #expect((object["arguments"] as? [String: Any])?["goal"] as? String == "film look")
  }

  @Test func outcomesAreReadFromTheAnswer() {
    func parse(_ text: String?) -> PluginToolOutcome { .parse(text.map { Data($0.utf8) }) }
    #expect(parse(#"{"type":"tool.result","text":"hi"}"#) == .text("hi"))
    #expect(parse(#"{"type":"tool.result","text":"no","isError":true}"#) == .failure("no"))
    #expect(parse(#"{"type":"error","text":"bad"}"#) == .failure("bad"))
    #expect(parse(#"{"type":"unsupported"}"#) != .text(""))
    #expect(parse(nil) == .failure("The plug-in did not answer in time."))
    let long = String(repeating: "x", count: PluginToolOutcome.maxLength + 10)
    #expect(parse(#"{"type":"tool.result","text":"\#(long)"}"#) == .text(String(long.prefix(PluginToolOutcome.maxLength))))
  }

  @Test func anActivePluginsToolIsAvailableAndCallable() async throws {
    let (registry, loader) = try loaded(tools: [list])
    #expect(registry.availableTools.map(\.declaration.name) == ["list_things"])
    loader.plugins["a"]?.answer = Data(#"{"type":"tool.result","text":"three things"}"#.utf8)
    let outcome = await registry.callTool(pluginID: "a", tool: "list_things", arguments: Data("{}".utf8))
    #expect(outcome == .text("three things"))
    #expect(loader.plugins["a"]?.sentTypes.contains("tool.call") == true)
  }

  @Test func anUndeclaredToolIsRefusedWithoutBotheringThePlugin() async throws {
    let (registry, loader) = try loaded(tools: [list])
    let before = loader.plugins["a"]?.sent.count
    let outcome = await registry.callTool(pluginID: "a", tool: "delete_all", arguments: Data("{}".utf8))
    guard case .failure = outcome else { Issue.record("expected a failure"); return }
    #expect(loader.plugins["a"]?.sent.count == before)
  }

  @Test func aPluginThatIsNotActiveOffersNoTools() async throws {
    let (registry, _) = try loaded(tools: [list])
    registry.setActive("a", false)
    #expect(registry.availableTools.isEmpty)
    let outcome = await registry.callTool(pluginID: "a", tool: "list_things", arguments: Data("{}".utf8))
    guard case .failure(let why) = outcome else { Issue.record("expected a failure"); return }
    #expect(why.contains("not active"))
  }

  @Test func aToolOfAnotherFamilyIsNotAvailable() throws {
    let other = PluginToolDeclaration(name: "other", description: "d", level: .read, families: ["sd15"])
    let (registry, _) = try loaded(tools: [list, other])
    #expect(registry.availableTools.map(\.declaration.name) == ["list_things"])
  }

  @Test func aPluginIncompatibleWithTheModelOffersNoTools() throws {
    let (registry, _) = try loaded(tools: [list], families: ["sd15"])
    #expect(registry.availableTools.isEmpty)
  }
}
