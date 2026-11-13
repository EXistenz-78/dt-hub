import DTHubPluginKit
import Foundation
import SwiftUI
import Testing

@testable import SphereLight

@MainActor
@Suite("Sphere Light tools")
struct SLToolsTests {
  let spy = Spy()
  let state: SLRState
  let folder: URL

  init() {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("slr-tools-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "slr-tools-\(UUID().uuidString)")!
    state = SLRState(store: SLRStore(defaults: defaults))
    state.active = true
    state.tempFolder = folder.path
  }

  func sender() -> SphereSender {
    let spy = spy
    return SphereSender(
      contribute: { spy.contributions.append($0); return spy.answer },
      registerPresets: { spy.presets.append($0); return ["type": "ok"] },
      saveFolder: folder.appendingPathComponent("Desktop"), size: 32, shadowSamples: 2, italian: false)
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let data = await SLTools.handle(call, state: state, sender: sender())
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in SLTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(SLTools.declarations.map(\.name) == ["get_status", "set_light", "remove_light", "send_sphere", "match_light"])
    #expect(SLTools.declarations.map(\.level) == [.read, .edit, .edit, .edit, .generate])
    let set = try #require(SLTools.declarations.first { $0.name == "set_light" })
    #expect(set.parameters.first { $0.name == "light" }?.required == true)
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SLTools.declarations)) is [[String: Any]])
    let plugin = SphereLightPlugin()
    #expect(plugin.manifest.tools?.count == 5 && plugin.manifest.version == "1.2")
    #expect(plugin.manifest.families == ["flux2_9b", "flux2_4b"])
  }

  @Test func theStatusShowsTheLightsAndTheRanges() async {
    let answer = await call("get_status")
    #expect(!answer.isError && !answer.startsRun)
    let json = answer.json
    let lights = json["lights"] as? [[String: Any]]
    #expect(lights?.count == 2 && lights?[0]["rotation"] as? Double == -135 && lights?[1]["hardness"] as? Double == 0.4 && lights?[0]["color"] as? String == "#FFFFFF")
    #expect(json["maxLights"] as? Int == 3 && json["passes"] as? Int == 1)
    #expect(!answer.text.contains("0000000000"))
  }

  @Test func anInactivePlugInRefusesEverything() async {
    state.active = false
    for tool in ["get_status", "set_light", "remove_light", "send_sphere", "match_light"] {
      #expect(await call(tool, ["light": 1, "target": "pipeline"]).isError, Comment(rawValue: tool))
    }
    #expect(spy.contributions.isEmpty)
  }

  @Test func setLightChangesOnlyWhatIsNamed() async {
    let before = state.lights[0]
    let answer = await call("set_light", ["light": 1, "rotation": 45, "color": "#FF8800"])
    #expect(!answer.isError)
    #expect(state.lights[0].rotationDeg == 45 && state.lights[0].elevationDeg == before.elevationDeg)
    #expect(state.lights[0].intensity == before.intensity)
    #expect(SLTools.hex(state.lights[0].color) == "#FF8800")
    #expect((answer.json["lights"] as? [[String: Any]])?[0]["color"] as? String == "#FF8800")
  }

  @Test func theNextNumberAddsALightUpToTheLimit() async {
    #expect(state.lights.count == 2)
    #expect(!(await call("set_light", ["light": 3, "elevation": 10])).isError)
    #expect(state.lights.count == 3 && state.lights[2].elevationDeg == 10)
    #expect(await call("set_light", ["light": 4]).isError)
    #expect(state.lights.count == 3)
  }

  @Test func badValuesChangeNothing() async {
    let before = state.lights
    #expect(await call("set_light", ["light": 1, "rotation": 45, "intensity": 9]).isError)
    #expect(await call("set_light", ["light": 1, "hardness": -1]).isError)
    #expect(await call("set_light", ["light": 1, "color": "red"]).isError)
    #expect(await call("set_light", ["light": 0]).isError)
    #expect(await call("set_light", ["light": 9]).isError)
    #expect(state.lights == before)
  }

  @Test func removeLightKeepsAtLeastOne() async {
    #expect(!(await call("remove_light", ["light": 2])).isError)
    #expect(state.lights.count == 1)
    #expect(await call("remove_light", ["light": 1]).isError)
    #expect(state.lights.count == 1)
    #expect(await call("remove_light", ["light": 2]).isError)
  }

  @Test func sendSphereToTheMoodboardDoesNotRun() async {
    let answer = await call("send_sphere", ["target": "moodboard"])
    #expect(!answer.isError && !answer.startsRun)
    #expect(spy.contributions.count == 1 && spy.contributions[0]["moodboard"] != nil && spy.contributions[0]["pipeline"] == nil)
    #expect(spy.presets.isEmpty)
    #expect(await call("send_sphere", ["target": "elsewhere"]).isError)
    #expect(await call("send_sphere").isError)
  }

  @Test func sendSphereAsAPipelineOffersThePresetsAndDoesNotRun() async throws {
    let answer = await call("send_sphere", ["target": "pipeline", "overcast": true])
    #expect(!answer.isError && !answer.startsRun)
    #expect(spy.presets.count == 1)
    let pipeline = try #require(spy.contributions.last?["pipeline"] as? [String: Any])
    #expect((pipeline["steps"] as? [Any])?.count == 2)
    #expect(answer.json["passes"] as? Int == 2 && state.overcast)
  }

  @Test func matchLightSendsThePipelineAndAsksTheAppToRun() async throws {
    let answer = await call("match_light")
    #expect(!answer.isError && answer.startsRun)
    let pipeline = try #require(spy.contributions.last?["pipeline"] as? [String: Any])
    #expect((pipeline["steps"] as? [Any])?.count == 1)
    #expect(answer.json["passes"] as? Int == 1)
    let withOvercast = await call("match_light", ["overcast": true])
    #expect(withOvercast.startsRun && withOvercast.json["passes"] as? Int == 2)
    #expect(state.isSending == false)
  }

  @Test func nothingIsWrittenToTheDesktopEvenIfTheBoxIsOn() async {
    state.saveToDesktop = true
    _ = await call("match_light")
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Desktop").path))
  }

  @Test func theAppRefusingIsAnErrorAndNeverStartsARun() async {
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    let answer = await call("match_light")
    #expect(answer.isError && !answer.startsRun && answer.text.contains("busy"))
    spy.answer = nil
    #expect(await call("match_light").isError)
    #expect(state.isSending == false)
  }

  @Test func withoutTheContextNothingIsSent() async {
    state.tempFolder = nil
    #expect(await call("match_light").isError)
    #expect(spy.contributions.isEmpty)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let reply = await SphereLightPlugin().handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
