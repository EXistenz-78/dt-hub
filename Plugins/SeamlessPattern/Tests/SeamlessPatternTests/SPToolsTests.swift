import CoreGraphics
import DTHubPluginKit
import Foundation
import Testing

@testable import SeamlessPattern

@MainActor
@Suite("Seamless Pattern tools")
struct SPToolsTests {
  private final class Wire: @unchecked Sendable {
    var sent: [Data] = []
    var answer: [String: Any]? = ["type": "ok", "conflicts": 0, "problems": [String]()]
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
  }

  private let wire = Wire()
  private let state: SPState
  private let folder: URL

  init() {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("sp-tools-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var store = SPStore()
    store.folder = folder
    let wire = wire
    state = SPState(store: store)
    state.send = { data in
      wire.sent.append(data)
      return wire.answer
    }
    state.active = true
  }

  private func ready(family: String = "krea_2", customServer: Bool? = true) async {
    await state.applyContext(family: family, customServer: customServer, lastResultPath: nil)
  }

  private func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let data = await SPTools.handle(call, state: state, connection: SPTools.Connection())
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  private func writePNG(_ image: CGImage) -> String {
    let url = folder.appendingPathComponent("p-\(UUID().uuidString).png")
    try? SPPNG.data(from: image)?.write(to: url)
    return url.path
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormed() {
    #expect(SPTools.declarations.map(\.name) == ["get_status", "set_mode", "prepare_run", "stop", "check_seam"])
    #expect(SPTools.declarations.map(\.level.rawValue) == ["read", "edit", "edit", "edit", "read"])
    for tool in SPTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    let mode = SPTools.declarations[1].parameters.first
    #expect(mode?.name == "mode" && mode?.required == true && mode?.values == ["both", "leftRight", "upDown"])
    let check = SPTools.declarations[4].parameters.first
    #expect(check?.name == "result_id" && check?.format == DTHubToolParameter.imageFormat)
  }

  // MARK: get_status

  @Test func theStatusSaysWhatTheTabKnows() async {
    await ready()
    let answer = await call("get_status")
    #expect(!answer.isError)
    let json = answer.json
    #expect(json["mode"] as? String == "both")
    #expect(json["prepared"] as? Bool == false)
    #expect(json["customServer"] as? Bool == true)
    #expect(json["family"] as? String == "krea_2")
    #expect(json["lastResult"] is NSNull)
    #expect(json["seam"] is NSNull)
  }

  @Test func theStatusShowsTheLastResultAndItsSeam() async {
    let path = writePNG(TestImages.make(128, 128) { x, y, c in (x * 2 + y + c * 10) % 256 })
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: path)
    let json = await call("get_status").json
    #expect(json["lastResult"] as? String == (path as NSString).lastPathComponent)
    let seam = json["seam"] as? [String: Any]
    #expect((seam?["leftRight"] as? [String: Any])?["status"] as? String != nil)
    #expect((seam?["upDown"] as? [String: Any])?["status"] as? String != nil)
  }

  @Test func theStatusOfAnAppWithoutTheFieldIsNull() async {
    await ready(customServer: nil)
    let json = await call("get_status").json
    #expect(json["customServer"] is NSNull)
  }

  @Test func theToolsRefuseWhenThePlugInIsNotActive() async {
    state.active = false
    #expect(await call("get_status").isError)
    #expect(await call("set_mode", ["mode": "upDown"]).isError)
    #expect(state.mode == .both)
  }

  // MARK: set_mode

  @Test func setModeChangesTheMode() async {
    await ready()
    for mode in ["leftRight", "upDown", "both"] {
      let answer = await call("set_mode", ["mode": mode])
      #expect(!answer.isError)
      #expect(answer.json["mode"] as? String == mode)
      #expect(state.mode.rawValue == mode)
    }
    #expect(wire.sent.isEmpty)
  }

  @Test func setModeWhilePreparedProposesThePipelineAgain() async {
    await ready()
    _ = await call("prepare_run")
    let answer = await call("set_mode", ["mode": "upDown"])
    #expect(!answer.isError && answer.json["prepared"] as? Bool == true)
    #expect(wire.sent.last == SPSender.prepare(mode: .upDown))
  }

  @Test func aModeThatDoesNotExistIsAnErrorAndChangesNothing() async {
    await ready()
    for arguments in [["mode": "diagonal"], [:], ["mode": 3]] as [[String: Any]] {
      let answer = await call("set_mode", arguments)
      #expect(answer.isError)
    }
    #expect(state.mode == .both && wire.sent.isEmpty)
  }

  // MARK: prepare_run and stop

  @Test func prepareRunProposesThePipelineAndAsksTheAppToRunIt() async {
    await ready()
    let answer = await call("prepare_run")
    #expect(!answer.isError && answer.startsRun)
    #expect(answer.json["prepared"] as? Bool == true)
    #expect(wire.sent == [SPSender.prepare(mode: .both)])
    #expect(state.isPrepared)
  }

  @Test func prepareRunWithoutTheCustomServerIsRefusedAndSendsNothing() async {
    for server in [false, nil] as [Bool?] {
      await ready(customServer: server)
      let answer = await call("prepare_run")
      #expect(answer.isError && !answer.startsRun)
      #expect(answer.text == "Seamless Pattern needs DT Hub's own server (Preferences › Draw Things: use the included server).")
    }
    #expect(wire.sent.isEmpty && !state.isPrepared)
  }

  @Test func prepareRunOnAnUnsupportedFamilyIsRefusedAndSendsNothing() async {
    await ready(family: "sdxl")
    let answer = await call("prepare_run")
    #expect(answer.isError && !answer.startsRun)
    #expect(answer.text == L.agentUnsupportedFamily)
    #expect(wire.sent.isEmpty && !state.isPrepared)
  }

  @Test func prepareRunSaysWhenTheAppDoesNotTakeThePipeline() async {
    await ready()
    wire.answer = ["type": "ok", "problems": ["Another pipeline is prepared."]]
    let answer = await call("prepare_run")
    #expect(answer.isError && !answer.startsRun)
    #expect(answer.text.contains("Another pipeline is prepared."))
    #expect(!state.isPrepared)
    wire.answer = nil
    let none = await call("prepare_run")
    #expect(none.isError && !none.startsRun)
  }

  @Test func stopWithdrawsThePipeline() async {
    await ready()
    _ = await call("prepare_run")
    let answer = await call("stop")
    #expect(!answer.isError && answer.json["prepared"] as? Bool == false)
    #expect(wire.sent.last == SPSender.stop())
    #expect(!state.isPrepared)
  }

  // MARK: check_seam

  @Test func checkSeamScoresAFileAsTheTabDoes() async throws {
    let image = TestImages.make(128, 96) { x, y, c in (x * 2 + y * 3 + c * 10) % 256 }
    let path = writePNG(image)
    let answer = await call("check_seam", ["result_id": path])
    #expect(!answer.isError)
    let expected = SPSeam.check(try #require(SPPNG.load(URL(fileURLWithPath: path))))
    let json = answer.json
    #expect((json["leftRight"] as? [String: Any])?["status"] as? String == expected.leftRight.status.rawValue)
    #expect((json["upDown"] as? [String: Any])?["status"] as? String == expected.upDown.status.rawValue)
    #expect(wire.sent.isEmpty)
  }

  @Test func checkSeamOfATinyPictureIsNotApplicable() async {
    let path = writePNG(TestImages.make(32, 32) { x, _, _ in x * 8 })
    let json = await call("check_seam", ["result_id": path]).json
    #expect((json["leftRight"] as? [String: Any])?["status"] as? String == "notApplicable")
  }

  @Test func checkSeamWithoutAnIdUsesThePictureOnShow() async {
    let path = writePNG(TestImages.make(128, 128) { x, y, _ in (x + y) % 256 })
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: path)
    #expect(!(await call("check_seam")).isError)
  }

  @Test func checkSeamWithoutAnIdAndWithoutAPictureIsAnError() async {
    await ready()
    #expect(await call("check_seam").isError)
  }

  @Test func checkSeamOfAnIdThatDoesNotExistIsAnError() async {
    await ready()
    let missing = folder.appendingPathComponent("nope.png").path
    #expect(await call("check_seam", ["result_id": missing]).isError)
    #expect(await call("check_seam", ["result_id": "r-does-not-exist"]).isError)
    let notAPicture = folder.appendingPathComponent("a.txt")
    try? Data("hello".utf8).write(to: notAPicture)
    #expect(await call("check_seam", ["result_id": notAPicture.path]).isError)
  }

  @Test func anUnknownToolIsUnsupported() async {
    let body: [String: Any] = ["type": "tool.call", "tool": "nope", "arguments": [:]]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let data = await SPTools.handle(call, state: state, connection: SPTools.Connection())
    #expect(DTHubMessage.type(of: data) == "unsupported")
  }
}
