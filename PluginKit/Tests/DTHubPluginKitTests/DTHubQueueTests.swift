import Foundation
import Testing

@testable import DTHubPluginKit

struct DTHubQueueTests {
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func captureParsesFolder() throws {
    let data = Data(#"{"type":"queue.capture","folder":"/tmp/entry/plugin"}"#.utf8)
    let request = try #require(DTHubQueueCapture(data))
    #expect(request.folder.path == "/tmp/entry/plugin")
  }

  @Test func captureWithoutFolderIsNil() {
    #expect(DTHubQueueCapture(Data(#"{"type":"queue.capture"}"#.utf8)) == nil)
  }

  @Test func prepareParsesStateModelFamily() throws {
    let data = Data(
      #"{"type":"queue.prepare","folder":"/tmp/e/plugin","state":{"factor":4,"image":"source.png"},"model":"flux.ckpt","family":"flux1"}"#
        .utf8)
    let request = try #require(DTHubQueuePrepare(data))
    #expect(request.folder.path == "/tmp/e/plugin")
    #expect(request.state["factor"] as? Int == 4)
    #expect(request.state["image"] as? String == "source.png")
    #expect(request.model == "flux.ckpt")
    #expect(request.family == "flux1")
  }

  @Test func prepareWithoutFamilyHasNilFamily() throws {
    let data = Data(#"{"type":"queue.prepare","folder":"/tmp/e","state":{},"model":"m"}"#.utf8)
    #expect(try #require(DTHubQueuePrepare(data)).family == nil)
  }

  @Test func prepareWithoutStateIsNil() {
    #expect(DTHubQueuePrepare(Data(#"{"type":"queue.prepare","folder":"/tmp/e"}"#.utf8)) == nil)
  }

  @Test func okCarriesState() throws {
    let message = try object(DTHubMessage.ok(state: ["image": "source.png"]))
    #expect(message["type"] as? String == "ok")
    #expect((message["state"] as? [String: Any])?["image"] as? String == "source.png")
  }

  @Test func okWithoutStateIsBare() throws {
    let message = try object(DTHubMessage.ok())
    #expect(message["type"] as? String == "ok")
    #expect(message["state"] == nil)
  }

  @Test func failureCarriesText() throws {
    let message = try object(DTHubMessage.failure("niente da fare"))
    #expect(message["type"] as? String == "error")
    #expect(message["text"] as? String == "niente da fare")
  }
}

struct DTHubToolTests {
  @Test func aToolCallIsReadWithItsArguments() throws {
    let data = Data(#"{"type":"tool.call","tool":"advise","arguments":{"goal":"film","n":2,"flag":true}}"#.utf8)
    let call = try #require(DTHubToolCall(data))
    #expect(call.tool == "advise" && call.string("goal") == "film" && call.number("n") == 2 && call.bool("flag") == true)
    #expect(call.number("flag") == nil && call.string("n") == nil)
    #expect(DTHubToolCall(Data(#"{"type":"context"}"#.utf8)) == nil)
    #expect(DTHubToolCall(Data(#"{"type":"tool.call","tool":"x"}"#.utf8))?.arguments.isEmpty == true)
  }

  @Test func theResultIsAToolResultWithTheErrorFlagOnlyWhenSet() throws {
    let ok = try #require(try JSONSerialization.jsonObject(with: DTHubMessage.toolResult("fine")) as? [String: Any])
    #expect(ok["type"] as? String == "tool.result" && ok["text"] as? String == "fine" && ok["isError"] == nil)
    let bad = try #require(try JSONSerialization.jsonObject(with: DTHubMessage.toolResult("no", isError: true)) as? [String: Any])
    #expect(bad["isError"] as? Bool == true)
  }

  @Test func theManifestCarriesTheTools() throws {
    let manifest = DTHubManifest(id: "a", name: "A", tools: [DTHubTool(name: "t", description: "d", level: .edit, timeout: 90)])
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
    let tool = (object["tools"] as? [[String: Any]])?.first
    #expect(tool?["name"] as? String == "t" && tool?["level"] as? String == "edit" && tool?["timeout"] as? Double == 90)
  }

  @Test func aToolResultCanAskTheAppToRunButNotWhenItFailed() throws {
    let go = try #require(try JSONSerialization.jsonObject(with: DTHubMessage.toolResult("go", startsRun: true)) as? [String: Any])
    #expect(go["startsRun"] as? Bool == true)
    let plain = try #require(try JSONSerialization.jsonObject(with: DTHubMessage.toolResult("fine")) as? [String: Any])
    #expect(plain["startsRun"] == nil)
    let failed = try #require(
      try JSONSerialization.jsonObject(with: DTHubMessage.toolResult("no", isError: true, startsRun: true)) as? [String: Any])
    #expect(failed["startsRun"] == nil)
  }

  @Test func aParameterCanBeAnImageAndWholeNumbersAreRead() throws {
    let tool = DTHubTool(
      name: "t", description: "d", parameters: [DTHubToolParameter(name: "image", description: "i", format: DTHubToolParameter.imageFormat)])
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool)) as? [String: Any])
    #expect(((object["parameters"] as? [[String: Any]])?.first)?["format"] as? String == "image")
    let body = try JSONSerialization.data(withJSONObject: ["type": "tool.call", "tool": "t", "arguments": ["n": 4, "x": 1.5, "b": true]])
    let call = try #require(DTHubToolCall(body))
    #expect(call.integer("n") == 4 && call.integer("x") == nil && call.integer("b") == nil && call.integer("missing") == nil)
  }
}
