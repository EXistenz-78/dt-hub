import CoreGraphics
import DTHubPluginKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import QwenInpainting

@MainActor
@Suite("Qwen Inpainting tools")
struct QIToolsTests {
  @MainActor
  final class Spy {
    var contributions: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok"]
    var asked: [String] = []
    var llm: DTHubLLMAnswer = .text("Rewritten prompt.")
  }

  let spy = Spy()
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qi-tools-\(UUID().uuidString)", isDirectory: true)
  let state: InpaintingState

  init() throws {
    state = InpaintingState(store: InpaintingStore(folder: nil), italian: false)
    state.active = true
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    state.apply(context: try context(start: try image("start.png")))
  }

  func image(_ name: String, width: Int = 400, height: Int = 200) throws -> String {
    let c = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let url = temp.appendingPathComponent(name)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil)
    CGImageDestinationFinalize(d)
    return url.path
  }

  func context(start: String?, enhancer: Bool = false) throws -> Data {
    var parts = [#""type":"context""#, #""tempFolder":"\#(temp.path)""#, #""family":"qwen_image_2.1""#]
    if let start { parts.append(#""startImage":"\#(start)""#) }
    let models = enhancer
      ? #"[{"name":"pe-i2i","path":"/nowhere","supportsImages":true,"family":"qwen_image_2.1","use":"i2i"}]"#
      : #"[{"name":"vl","path":"/nowhere","supportsImages":true}]"#
    parts.append(#""languageModels":\#(models)"#)
    return Data(("{" + parts.joined(separator: ",") + "}").utf8)
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
    var marks: [[String: Any]] { json["marks"] as? [[String: Any]] ?? [] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let spy = self.spy
    let state = self.state
    let connection = QITools.Connection(send: {
      await state.send(
        using: { text, _, _, model in
          spy.asked.append(text + "|" + model)
          return spy.llm
        },
        contribute: { spy.contributions.append($0); return spy.answer })
    })
    let data = await QITools.handle(call, state: state, connection: connection)
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in QITools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(
      QITools.declarations.map(\.name) == [
        "get_status", "add_mark", "remove_mark", "clear_marks", "undo_mark", "set_card_text", "preview_drawing", "send_drawing",
      ])
    // Nothing generates: the agent runs through the app's own run.
    #expect(QITools.declarations.map(\.level) == [.read, .edit, .edit, .edit, .edit, .edit, .read, .edit])
    let add = try #require(QITools.declarations.first { $0.name == "add_mark" })
    #expect(add.parameters.first { $0.name == "tool" }?.values == ["sketch", "box", "circle", "arrow"])
    #expect(add.parameters.first { $0.name == "color" }?.values?.count == 9)
    #expect(try #require(QITools.declarations.last).timeout == 600)
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(QITools.declarations)) is [[String: Any]])
    let plugin = QwenInpaintingPlugin()
    #expect(plugin.manifest.tools?.count == 8 && plugin.manifest.version == "1.3")
    #expect(plugin.manifest.families == ["qwen_image_2.1"])
  }

  // MARK: Reading

  @Test func theStatusShowsTheImageTheMarksAndTheCards() async {
    let empty = await call("get_status")
    #expect(!empty.isError && !empty.startsRun)
    #expect(empty.json["hasStartImage"] as? Bool == true && empty.json["canSend"] as? Bool == false)
    #expect((empty.json["problems"] as? [String]) == ["No mark yet."])
    #expect((empty.json["startImage"] as? [String: Any])?["width"] as? Int == 400)
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.2, "x2": 0.5, "y2": 0.6])
    _ = await call("set_card_text", ["tool": "box", "color": "red", "text": "put a lamp"])
    let status = await call("get_status")
    #expect(status.marks.count == 1 && status.marks[0]["tool"] as? String == "box")
    #expect((status.json["cards"] as? [[String: Any]])?.first?["text"] as? String == "put a lamp")
    #expect((status.json["prompt"] as? String)?.hasPrefix("Inside the red box: put a lamp.") == true)
    #expect(status.json["canSend"] as? Bool == true && !status.text.contains("0000000"))
  }

  @Test func anInactivePlugInRefusesEverything() async {
    state.active = false
    for tool in QITools.declarations.map(\.name) {
      #expect(await call(tool, ["tool": "box", "color": "red", "mark": 1, "text": "x"]).isError, Comment(rawValue: tool))
    }
    #expect(state.session.marks.isEmpty && spy.contributions.isEmpty)
  }

  // MARK: Marks

  @Test func everyKindOfMarkIsAddedWithItsOwnArguments() async {
    #expect(!(await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4])).isError)
    #expect(!(await call("add_mark", ["tool": "circle", "color": "blue", "width": 40, "x1": 0.5, "y1": 0.1, "x2": 0.9, "y2": 0.5])).isError)
    #expect(!(await call("add_mark", ["tool": "arrow", "color": "green", "x1": 0.1, "y1": 0.9, "x2": 0.5, "y2": 0.6])).isError)
    let sketch = await call("add_mark", ["tool": "sketch", "color": "yellow", "points": "0.1,0.1 0.2,0.3 0.3,0.2"])
    #expect(!sketch.isError && sketch.marks.count == 4)
    #expect(state.session.marks.map(\.tool) == [.box, .circle, .arrow, .sketch] && state.session.marks[1].width == 40)
    #expect(state.session.marks[3].points == [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.3, y: 0.2)])
  }

  @Test func badMarksAreRefusedAndNothingChanges() async {
    let bad: [[String: Any]] = [
      ["tool": "triangle", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4],
      ["tool": "box", "color": "orange", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4],
      ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 1.2, "y2": 0.4],
      ["tool": "box", "color": "red", "x1": -0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4],
      ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4],
      ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.1, "y2": 0.4],
      ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4, "width": 3],
      ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4, "width": 129],
      ["tool": "box", "color": "red", "points": "0.1,0.1 0.2,0.2"],
      ["tool": "arrow", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.1, "y2": 0.1],
      ["tool": "sketch", "color": "red"],
      ["tool": "sketch", "color": "red", "points": "0.1,0.1"],
      ["tool": "sketch", "color": "red", "points": "0.1,0.1 2,0.3"],
      ["tool": "sketch", "color": "red", "points": "a,b c,d"],
      ["tool": "sketch", "color": "red", "points": "0.1,0.1 0.2,0.2", "x1": 0.1],
    ]
    for arguments in bad { #expect(await call("add_mark", arguments).isError, Comment(rawValue: "\(arguments)")) }
    #expect(state.session.marks.isEmpty)
  }

  @Test func aMarkNeedsAStartImageAndThereIsALimit() async throws {
    for _ in 0..<Mark.maxMarks {
      #expect(!(await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4])).isError)
    }
    #expect(await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4]).isError)
    state.apply(context: try context(start: nil))
    #expect(state.session.marks.isEmpty)
    #expect(await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4]).isError)
  }

  @Test func removeClearAndUndo() async {
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4])
    _ = await call("add_mark", ["tool": "box", "color": "blue", "x1": 0.5, "y1": 0.5, "x2": 0.9, "y2": 0.9])
    let tooHigh = await call("remove_mark", ["mark": 3])
    let zero = await call("remove_mark", ["mark": 0])
    #expect(tooHigh.isError && zero.isError)
    #expect(!(await call("remove_mark", ["mark": 1])).isError && state.session.marks.map(\.color) == [.blue])
    #expect(!(await call("undo_mark")).isError && state.session.marks.map(\.color) == [.red, .blue])
    #expect(!(await call("undo_mark", ["redo": true])).isError && state.session.marks.map(\.color) == [.blue])
    #expect(!(await call("clear_marks")).isError && state.session.marks.isEmpty)
    #expect(await call("remove_mark", ["mark": 1]).isError)
    #expect(!(await call("undo_mark")).isError && state.session.marks.count == 1)
  }

  @Test func theTextOfACardIsKeptAfterItsMarksAreGone() async {
    _ = await call("set_card_text", ["tool": "circle", "color": "cyan", "text": "a moon"])
    #expect(state.session.texts["cyan:circle"] == "a moon")
    #expect(await call("set_card_text", ["tool": "circle", "color": "cyan", "text": String(repeating: "a", count: QITools.maxText + 1)]).isError)
    #expect(await call("set_card_text", ["tool": "ring", "color": "cyan", "text": "x"]).isError)
    #expect(await call("set_card_text", ["tool": "circle", "color": "cyan"]).isError)
    _ = await call("set_card_text", ["tool": "circle", "color": "cyan", "text": ""])
    #expect(state.session.texts["cyan:circle"] == "")
  }

  @Test func changingTheStartImageDropsTheMarksButKeepsTheTexts() async throws {
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4])
    _ = await call("set_card_text", ["tool": "box", "color": "red", "text": "a lamp"])
    state.apply(context: try context(start: try image("other.png", width: 300, height: 300)))
    #expect(state.session.marks.isEmpty && state.session.texts["red:box"] == "a lamp")
    #expect((await call("get_status")).marks.isEmpty)
  }

  // MARK: Preview and send

  @Test func thePreviewIsAPictureWithTheMarks() async throws {
    #expect(await call("preview_drawing").isError)
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.9, "y2": 0.9, "width": 20])
    let answer = await call("preview_drawing")
    #expect(!answer.isError)
    let path = try #require(answer.json["path"] as? String)
    #expect(path.hasPrefix(temp.path) && FileManager.default.fileExists(atPath: path))
    #expect(answer.json["width"] as? Int == 400)
  }

  @Test func sendNeedsAMarkAndSendsTheDrawingAndThePromptWithoutRunning() async throws {
    #expect(await call("send_drawing").isError)
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.2, "x2": 0.5, "y2": 0.6])
    _ = await call("set_card_text", ["tool": "box", "color": "red", "text": "a brass lamp"])
    let answer = await call("send_drawing")
    #expect(!answer.isError && !answer.startsRun, Comment(rawValue: answer.text))
    let body = try #require(spy.contributions.last)
    let paint = try #require(body["paint"] as? [String: Any])
    #expect(FileManager.default.fileExists(atPath: try #require(paint["path"] as? String)))
    #expect((body["fields"] as? [String: Any])?["prompt"] as? String == Cards.prompt(marks: state.session.marks, texts: state.session.texts))
    #expect(answer.json["sent"] as? Bool == true && state.isSending == false && spy.asked.isEmpty)
  }

  @Test func theEnhancerIsUsedOnlyWhenThereIsOne() async throws {
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.2, "x2": 0.5, "y2": 0.6])
    _ = await call("set_card_text", ["tool": "box", "color": "red", "text": "a lamp"])
    #expect(await call("send_drawing", ["enhance": true]).isError)
    state.apply(context: try context(start: try image("start.png"), enhancer: true))
    let answer = await call("send_drawing", ["enhance": true])
    #expect(!answer.isError && spy.asked.count == 1 && spy.asked[0].hasSuffix("|pe-i2i"))
    #expect((spy.contributions.last?["fields"] as? [String: Any])?["prompt"] as? String == "Rewritten prompt.")
    #expect(answer.json["enhanced"] as? Bool == true && answer.json["prompt"] as? String == "Rewritten prompt.")
    spy.llm = .failure("out of memory")
    let fallback = await call("send_drawing")
    #expect(!fallback.isError && fallback.json["enhanced"] as? Bool == false && fallback.json["prompt"] as? String == state.composedPrompt)
    #expect((spy.contributions.last?["fields"] as? [String: Any])?["prompt"] as? String == state.composedPrompt)
  }

  @Test func aDrawingWithoutTextSendsOnlyTheDrawing() async {
    _ = await call("add_mark", ["tool": "arrow", "color": "red", "x1": 0.1, "y1": 0.2, "x2": 0.5, "y2": 0.6])
    let answer = await call("send_drawing")
    #expect(!answer.isError && spy.contributions.last?["fields"] == nil && answer.json["prompt"] is NSNull)
  }

  @Test func theAppRefusingIsAnError() async {
    _ = await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.2, "x2": 0.5, "y2": 0.6])
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    let answer = await call("send_drawing")
    #expect(answer.isError && answer.text.contains("busy") && state.isSending == false)
    spy.answer = nil
    #expect(await call("send_drawing").isError)
  }

  @Test func aBusyPlugInRefusesChanges() async {
    state.isSending = true
    let results = [
      await call("add_mark", ["tool": "box", "color": "red", "x1": 0.1, "y1": 0.1, "x2": 0.4, "y2": 0.4]),
      await call("clear_marks"), await call("set_card_text", ["tool": "box", "color": "red", "text": "x"]), await call("send_drawing"),
    ]
    let allRefused = results.allSatisfy { $0.isError }
    #expect(allRefused)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let reply = await QwenInpaintingPlugin().handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
