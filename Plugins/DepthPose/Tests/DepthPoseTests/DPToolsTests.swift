import CoreGraphics
import DTHubPluginKit
import Foundation
import Testing

@testable import DepthPose

@MainActor
@Suite("DPTools")
struct DPToolsTests {
  let state: DPState
  let root: URL
  let sent = Sent()
  let detector: FakeDetector

  @MainActor
  final class Sent {
    var contributions: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok", "conflicts": 0]
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var type: String?
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
  }

  init(depthReady: Bool = true) async throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("dptools-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let downloader = FakeDownloader()
    downloader.contents = ["Manifest.json": Data("{}".utf8)]
    let models = DPModelStore(
      folder: root.appendingPathComponent("model"),
      files: [DPModelFile(path: "M.mlpackage/Manifest.json", size: 2, sha256: nil)], packageName: "M.mlpackage",
      downloader: downloader,
      compile: { package in
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).mlmodelc")
        try FileManager.default.copyItem(at: package, to: out)
        try Data("ok".utf8).write(to: out.appendingPathComponent("marker"))
        return out
      },
      validate: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("marker").path) })
    if depthReady { try await models.install { _ in } }
    detector = FakeDetector(people: [standingPerson])
    state = DPState(
      store: DPStore(defaults: UserDefaults(suiteName: "dp-tools-\(UUID().uuidString)")!), models: models, detector: detector,
      makeDepth: { _ in DepthEstimator(model: FakeDepthModel()) }, italian: false)
    state.tempFolder = root.appendingPathComponent("temp").path
    state.active = true
    await state.refreshModelState()
  }

  func picture(_ width: Int = 80, _ height: Int = 60, name: String = "photo.png") -> String {
    let url = root.appendingPathComponent(name)
    try! Pictures.data(Pictures.image(width: width, height: height)).write(to: url)
    return url.path
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    await DPToolsTests.call(tool, arguments, state: state, sent: sent)
  }

  static func call(_ tool: String, _ arguments: [String: Any], state: DPState, sent: Sent) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let answer = await DPTools.handle(
      call, state: state,
      connection: DPTools.Connection(contribute: { message in
        sent.contributions.append(message)
        return sent.answer
      }))
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false, type: object["type"] as? String)
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndNoneGenerates() throws {
    for tool in DPTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
      #expect(tool.families == nil, "the plug-in's own compatibility (an edit model) decides")
    }
    #expect(DPTools.declarations.map(\.name) == ["get_status", "make_maps", "send_to_moodboard"])
    #expect(DPTools.declarations.map(\.level) == [.read, .edit, .edit])
    let make = try #require(DPTools.declarations.first { $0.name == "make_maps" })
    #expect(make.parameters.first { $0.name == "image" }?.format == "image")
    #expect(make.parameters.filter { $0.type == "boolean" }.map(\.name) == ["depth", "pose", "send_to_moodboard"])
    #expect(DepthPosePlugin().manifest.tools?.map(\.name) == DPTools.declarations.map(\.name))
  }

  @Test func theManifestJSONCarriesTheTools() throws {
    let data = try JSONEncoder().encode(DepthPosePlugin().manifest)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((object["tools"] as? [[String: Any]])?.count == 3)
  }

  // MARK: Reading

  @Test func statusOfAnEmptyTab() async {
    let answer = await call("get_status")
    #expect(!answer.isError)
    #expect(answer.json["hasPicture"] as? Bool == false)
    #expect(answer.json["depthModel"] as? String == "ready")
    #expect(answer.json["poseSource"] as? String == "Vision (body only)")
  }

  @Test func toolsRefuseWhenThePluginIsNotActive() async {
    state.active = false
    for tool in ["get_status", "make_maps", "send_to_moodboard"] {
      let answer = await call(tool, tool == "make_maps" ? ["image": picture()] : [:])
      #expect(answer.isError, Comment(rawValue: tool))
    }
  }

  @Test func toolsRefuseBeforeTheFirstContext() async {
    state.tempFolder = nil
    #expect(await call("get_status").isError)
  }

  // MARK: Making

  @Test func makeMapsMakesBothAndLeavesThemOnTheTab() async throws {
    let answer = await call("make_maps", ["image": picture(), "depth": true, "pose": true])
    #expect(!answer.isError && !answer.startsRun)
    #expect((answer.json["depthMap"] as? [String: Any])?["width"] as? Int == 80)
    #expect(answer.json["poseMapMade"] as? Bool == true)
    #expect(state.depthImage != nil && state.poseImage != nil)
    #expect(state.wantsDepth && state.wantsPose)
    #expect(sent.contributions.isEmpty, "nothing goes to the Moodboard unless asked")
    let status = await call("get_status")
    #expect(status.json["depthMapMade"] as? Bool == true)
    #expect((status.json["picture"] as? [String: Any])?["name"] as? String == "photo.png")
  }

  @Test func makeMapsCanSendToTheMoodboardAtOnce() async throws {
    let answer = await call("make_maps", ["image": picture(), "depth": true, "pose": true, "send_to_moodboard": true])
    #expect(!answer.isError)
    #expect(answer.json["sentToMoodboard"] as? Bool == true)
    let moodboard = try #require(sent.contributions.last?["moodboard"] as? [[String: Any]])
    #expect(moodboard.map { $0["name"] as? String } == ["Depth", "Pose"])
    for entry in moodboard { #expect(FileManager.default.fileExists(atPath: try #require(entry["path"] as? String))) }
  }

  @Test func theTabsTicksAreUsedWhenTheCallNamesNone() async {
    state.select(depth: false, pose: true)
    let answer = await call("make_maps", ["image": picture()])
    #expect(!answer.isError)
    #expect(state.depthImage == nil && state.poseImage != nil)
    #expect(answer.json["depthMapMade"] as? Bool == false)
  }

  @Test func makeMapsWithoutImageUsesThePictureOnTheTab() async {
    state.setImage(file: URL(fileURLWithPath: picture(name: "tab.png")))
    let answer = await call("make_maps", ["depth": true])
    #expect(!answer.isError)
    #expect((answer.json["picture"] as? [String: Any])?["name"] as? String == "tab.png")
  }

  @Test func noPictureIsAnError() async {
    let answer = await call("make_maps", ["depth": true])
    #expect(answer.isError && answer.text.contains("No picture"))
  }

  @Test func anUnreadablePictureChangesNothing() async throws {
    state.setImage(file: URL(fileURLWithPath: picture(name: "keep.png")))
    let bad = root.appendingPathComponent("bad.png")
    try Data("not an image".utf8).write(to: bad)
    let answer = await call("make_maps", ["image": bad.path, "pose": true])
    #expect(answer.isError)
    #expect(state.imageName == "keep.png")
  }

  @Test func choosingNoMapIsAnError() async {
    let answer = await call("make_maps", ["image": picture(), "depth": false, "pose": false])
    #expect(answer.isError && answer.text.contains("at least one"))
    #expect(state.image == nil, "nothing changed")
  }

  @Test func depthAloneWithoutItsModelIsRefusedAndNothingChanges() async throws {
    let missing = try await DPToolsTests(depthReady: false)
    let answer = await DPToolsTests.call(
      "make_maps", ["image": missing.picture(), "depth": true, "pose": false], state: missing.state, sent: missing.sent)
    #expect(answer.isError && answer.text.contains("not downloaded"))
    #expect(missing.state.image == nil)
  }

  @Test func depthAndPoseWithoutTheDepthModelGivesThePoseAndSaysSo() async throws {
    let missing = try await DPToolsTests(depthReady: false)
    let answer = await DPToolsTests.call(
      "make_maps", ["image": missing.picture(), "depth": true, "pose": true], state: missing.state, sent: missing.sent)
    #expect(!answer.isError)
    #expect(answer.json["depthMapMade"] as? Bool == false && answer.json["poseMapMade"] as? Bool == true)
    #expect((answer.json["notice"] as? String)?.isEmpty == false)
  }

  @Test func aPictureWithNobodyGivesNoPoseAndAnErrorWhenItWasTheOnlyMap() async {
    detector.people = []
    let answer = await call("make_maps", ["image": picture(), "depth": false, "pose": true])
    #expect(answer.isError)
    #expect(state.poseImage == nil)
  }

  // MARK: Sending

  @Test func sendToMoodboardNeedsMaps() async {
    let answer = await call("send_to_moodboard")
    #expect(answer.isError)
    #expect(sent.contributions.isEmpty)
  }

  @Test func sendToMoodboardSendsTheTickedMaps() async throws {
    _ = await call("make_maps", ["image": picture(), "depth": true, "pose": false])
    let answer = await call("send_to_moodboard")
    #expect(!answer.isError && answer.json["sentToMoodboard"] as? Bool == true)
    let moodboard = try #require(sent.contributions.last?["moodboard"] as? [[String: Any]])
    #expect(moodboard.map { $0["name"] as? String } == ["Depth"])
  }

  @Test func anAppThatRefusesIsReportedAsAnError() async {
    _ = await call("make_maps", ["image": picture(), "depth": true, "pose": false])
    sent.answer = ["type": "error", "text": "Moodboard is full"]
    let answer = await call("send_to_moodboard")
    #expect(answer.isError && answer.text.contains("Moodboard is full"))
    sent.answer = nil
    #expect(await call("send_to_moodboard").isError)
  }

  @Test func makeMapsWithARefusingAppKeepsTheMapsAndReportsNotSent() async {
    sent.answer = ["type": "error", "text": "no"]
    let answer = await call("make_maps", ["image": picture(), "depth": true, "pose": false, "send_to_moodboard": true])
    #expect(!answer.isError)
    #expect(answer.json["sentToMoodboard"] as? Bool == false)
    #expect(state.depthImage != nil)
  }

  // MARK: The plug-in's message channel

  @Test func thePluginWithoutAHostDoesNotTakeToolCalls() async {
    let plugin = DepthPosePlugin()
    let answer = await plugin.handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    #expect(answer.flatMap { DTHubMessage.type(of: $0) } == "unsupported", "no host yet: the plug-in has not started")
  }

  @Test func anUnknownToolIsUnsupported() async {
    let answer = await call("nothing")
    #expect(answer.type == "unsupported")
  }
}
