import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterMing

@MainActor
@Suite("The MCP tools")
struct ToolsTests {
  let state = Fixture.state()

  func call(_ tool: String, _ arguments: [String: Any] = [:], send: PromptSender.Outcome? = nil,
            resized: @escaping (PixelSize) -> Bool = { _ in true }) async -> (text: String, isError: Bool) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let actions = MingTools.Actions(write: { nil }, compose: { nil }, send: { send }, resize: { resized($0) })
    let answer = await MingTools.handle(call, state: state, actions: actions)
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false)
  }

  func object(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.drop { $0 != "{" }.utf8))) as? [String: Any] ?? [:]
  }

  @Test func theDeclarationsAreWellFormedAndNoneStartsAGeneration() throws {
    for tool in MingTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20 && tool.level != .generate)
    }
    #expect(MingTools.declarations.filter { $0.level == .read }.map(\.name) == ["get_status", "search_terms"])
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(MingTools.declarations)) is [[String: Any]])
    let plugin = MingPlugin(
      dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("ming-p-\(UUID().uuidString)"),
      store: MingStore(storage: MemoryStorage()))
    #expect(plugin.manifest.tools?.map(\.name) == MingTools.declarations.map(\.name))
    #expect(plugin.manifest.families?.contains("ming_image") == true)
  }

  @Test func layersAreAddedChangedMovedAndRemoved() async throws {
    #expect(!(await call("set_brief", ["image_style": "poster", "ambient_lighting": "soft", "idea": "x"])).isError)
    let first = object(await call("add_layer", ["description": "bg", "coordinates": "cx: 0.5, cy: 0.5, w: 1, h: 1"]).text)
    let id = try #require(first["id"] as? Int)
    let second = object(await call("add_layer", ["text": "HI", "description": "red", "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.3]).text)
    let textID = try #require(second["id"] as? Int)
    #expect(state.document.layers.last?.kind == .text)
    #expect(!(await call("set_layer", ["id": textID, "colors": "#ff0000, 00ff00", "relation": "top"])).isError)
    #expect(state.document.layers.last?.colors == ["#FF0000", "#00FF00"])
    #expect(await call("set_layer", ["id": textID, "colors": "red"]).isError)
    #expect(!(await call("move_layer", ["id": textID, "steps": -1])).isError)
    #expect(state.document.layers.map(\.id) == [textID, id])
    #expect(!(await call("remove_layer", ["id": textID])).isError)
    #expect(await call("remove_layer", ["id": 99]).isError)
    #expect(!(await call("send_to_generation", send: .init(status: "Sent", sent: true))).isError)
  }

  @Test func importReadsTheGenerationPromptOrTheGivenJSONAndResizes() async {
    var asked: PixelSize?
    state.update(generationPrompt: Fixture.familyStyle)
    let result = object(await call("import_json", resized: { asked = $0; return true }).text)
    #expect(asked == PixelSize(width: 1248, height: 832) && result["resizedTo"] != nil)
    #expect(state.document.layers.count == 3)
    #expect(await call("import_json", ["json": "nope"]).isError)
    #expect(state.document.layers.count == 3)
    asked = nil
    #expect(!(await call("import_json", ["json": Fixture.golden, "resize": false], resized: { asked = $0; return true })).isError)
    #expect(asked == nil && state.document.layers.count == 2)
  }
}
