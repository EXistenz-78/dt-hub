import CoreGraphics
import DTHubPluginKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import QwenInpainting

@MainActor
@Suite("Inpainting state")
struct InpaintingStateTests {
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qi-state-\(UUID().uuidString)", isDirectory: true)

  /// A white PNG of `width × height` on disk, as a start image of the app.
  func startImage(_ name: String = "start.png", width: Int = 400, height: Int = 200) throws -> String {
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
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

  func contextData(start: String?, pe: Bool = false) -> Data {
    var parts = [#""type":"context""#, #""tempFolder":"\#(temp.path)""#, #""family":"qwen_image_2.1""#]
    if let start { parts.append(#""startImage":"\#(start)""#) }
    let model = pe
      ? #"[{"name":"pe-i2i","path":"/nowhere","supportsImages":true,"family":"qwen_image_2.1","use":"i2i"}]"#
      : #"[{"name":"vl","path":"/nowhere","supportsImages":true}]"#
    parts.append(#""languageModels":\#(model)"#)
    return Data(("{" + parts.joined(separator: ",") + "}").utf8)
  }

  func state(start: String?, pe: Bool = false) -> InpaintingState {
    let s = InpaintingState(store: InpaintingStore(folder: nil), italian: false)
    s.apply(context: contextData(start: start, pe: pe))
    s.active = true
    return s
  }

  func box(_ color: MarkColor = .red) -> Mark {
    Mark(tool: .box, color: color, width: 8, points: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8)])
  }

  final class Log {
    var sent: [[String: Any]] = []
    var asked: [(text: String, images: [String], system: String, model: String)] = []
  }

  func contribute(_ log: Log, answer: [String: Any]? = ["type": "ok"]) -> InpaintingState.Contribute {
    { body in
      log.sent.append(body)
      return answer
    }
  }

  func ask(_ log: Log, _ answer: DTHubLLMAnswer) -> InpaintingState.Ask {
    { text, images, system, model in
      log.asked.append((text, images, system, model))
      return answer
    }
  }

  // MARK: Undo

  @Test func undoAndRedoStepThroughTheMarks() throws {
    let s = state(start: try startImage())
    s.add(box()); s.add(box(.blue)); s.add(box(.green))
    s.undo(); s.undo()
    #expect(s.session.marks.count == 1)
    s.redo()
    #expect(s.session.marks.count == 2)
    s.undo()
    s.add(box(.yellow))
    #expect(!s.canRedo)  // a new mark empties Redo
  }

  @Test func theUndoStackKeepsAtMost100StepsAndClearAllCanBeUndone() throws {
    let s = state(start: try startImage())
    for _ in 0..<120 { s.add(box()) }
    var undone = 0
    while s.canUndo { s.undo(); undone += 1 }
    #expect(undone == 100)
    let t = state(start: try startImage())
    t.add(box()); t.add(box())
    t.clearAll()
    #expect(t.session.marks.isEmpty)
    t.undo()
    #expect(t.session.marks.count == 2)
  }

  @Test func neverMoreThan200Marks() throws {
    let s = state(start: try startImage())
    for _ in 0..<210 { s.add(box()) }
    #expect(s.session.marks.count == 200)
  }

  // MARK: The start image

  @Test func anotherStartImageClearsTheMarksAndUndoButKeepsTheTexts() throws {
    let a = try startImage("a.png")
    let b = try startImage("b.png")
    let s = state(start: a)
    s.add(box())
    s.setText("make it blue", for: CardKey(color: .red, tool: .box))
    s.apply(context: contextData(start: b))
    #expect(s.session.marks.isEmpty && !s.canUndo && !s.canRedo)
    #expect(s.session.texts["red:box"] == "make it blue" && s.session.startImage == b)
    // The same image again changes nothing; no image after one clears.
    s.add(box())
    s.apply(context: contextData(start: b))
    #expect(s.session.marks.count == 1)
    s.apply(context: contextData(start: nil))
    #expect(s.session.marks.isEmpty && s.session.startImage == nil)
  }

  @Test func reopeningAProjectWithTheSameImageKeepsTheMarks() throws {
    let a = try startImage("a.png")
    let dir = temp.appendingPathComponent("project", isDirectory: true)
    var saved = InpaintingSession()
    saved.startImage = a
    saved.marks = [box(), box(.blue)]
    InpaintingStore(folder: dir).save(saved)
    let s = state(start: nil)
    s.switchProject(folder: dir)
    s.apply(context: contextData(start: a))
    #expect(s.session.marks.count == 2)
  }

  @Test func theTextOfAHiddenCardIsKeptAndComesBack() throws {
    let s = state(start: try startImage())
    s.add(box())
    s.setText("make it blue", for: CardKey(color: .red, tool: .box))
    s.undo()
    #expect(s.cards.isEmpty && s.session.texts["red:box"] == "make it blue")
    s.add(box())
    #expect(s.composedPrompt.hasPrefix("Inside the red box: make it blue."))
  }

  // MARK: Sending

  @Test func withoutTheEnhancerThePromptGoesDirectlyWithTheDrawing() async throws {
    let start = try startImage(width: 400, height: 200)
    let s = state(start: start)
    s.add(box())
    s.setText("make it blue", for: CardKey(color: .red, tool: .box))
    let log = Log()
    await s.send(using: ask(log, .text("unused")), contribute: contribute(log))
    let body = try #require(log.sent.first)
    let paint = try #require(body["paint"] as? [String: Any])
    let path = try #require(paint["path"] as? String)
    #expect(FileManager.default.fileExists(atPath: path) && paint["name"] as? String == "Qwen 2.1 Inpainting")
    #expect(Rasterizer.imageSize(at: path) == CGSize(width: 400, height: 200))
    #expect((body["fields"] as? [String: Any])?["prompt"] as? String == s.composedPrompt)
    #expect(log.asked.isEmpty && s.status == "Sent.")
  }

  @Test func withoutAnyTextThereIsNoPromptField() async throws {
    let s = state(start: try startImage())
    s.add(box())
    let log = Log()
    await s.send(using: ask(log, .text("x")), contribute: contribute(log))
    #expect(log.sent.first?["fields"] == nil && log.sent.first?["paint"] != nil)
  }

  @Test func aPortraitStartImageGivesAPortraitDrawing() async throws {
    let s = state(start: try startImage(width: 768, height: 1344))
    s.add(box())
    let log = Log()
    await s.send(using: ask(log, .text("x")), contribute: contribute(log))
    let path = try #require((log.sent.first?["paint"] as? [String: Any])?["path"] as? String)
    #expect(Rasterizer.imageSize(at: path) == CGSize(width: 768, height: 1344))
  }

  @Test func theEnhancerRewritesThePromptFromTheFusedPicture() async throws {
    let s = state(start: try startImage(), pe: true)
    s.add(box())
    s.setText("make it blue", for: CardKey(color: .red, tool: .box))
    let log = Log()
    await s.send(using: ask(log, .text("  \"Better.\" ")), contribute: contribute(log))
    let asked = try #require(log.asked.first)
    #expect(asked.text == PromptEnhancer.request(composed: s.composedPrompt) && asked.model == "pe-i2i")
    #expect(asked.images.count == 1 && FileManager.default.fileExists(atPath: asked.images[0]))
    #expect(asked.system == PromptEnhancer.builtInSystem)
    #expect((log.sent.first?["fields"] as? [String: Any])?["prompt"] as? String == "Better.")
  }

  @Test func ifTheEnhancerFailsTheDirectPromptGoesAndTheStatusSaysWhy() async throws {
    let s = state(start: try startImage(), pe: true)
    s.add(box())
    s.setText("make it blue", for: CardKey(color: .red, tool: .box))
    let log = Log()
    await s.send(using: ask(log, .failure("no memory")), contribute: contribute(log))
    #expect((log.sent.first?["fields"] as? [String: Any])?["prompt"] as? String == s.composedPrompt)
    #expect(s.status.contains("no memory") && s.status.contains("Enhancer not available"))
  }

  @Test func withTheEnhancerOffItIsNotAsked() async throws {
    let s = state(start: try startImage(), pe: true)
    s.session.usePE = false
    s.add(box())
    s.setText("x", for: CardKey(color: .red, tool: .box))
    let log = Log()
    await s.send(using: ask(log, .text("never")), contribute: contribute(log))
    #expect(log.asked.isEmpty)
  }

  @Test func theAnswerOfTheAppBecomesTheStatus() async throws {
    let s = state(start: try startImage())
    s.add(box())
    let log = Log()
    await s.send(using: ask(log, .text("x")), contribute: contribute(log, answer: ["type": "ok", "conflicts": 1]))
    #expect(s.status == "Sent. 1 conflict(s) waiting in the app." && !s.statusIsError)
    await s.send(using: ask(log, .text("x")), contribute: contribute(log, answer: ["type": "error", "text": "x"]))
    #expect(s.statusIsError && s.status == "x")
    await s.send(using: ask(log, .text("x")), contribute: contribute(log, answer: nil))
    #expect(s.statusIsError && s.status == "No answer from the app.")
    await s.send(using: ask(log, .text("x")), contribute: contribute(log, answer: ["problems": ["paint: there is no start image."]]))
    #expect(s.statusIsError && s.status.contains("paint: there is no start image."))
  }

  @Test func sendNeedsAnImageAMarkAndTheSwitchOn() throws {
    let s = state(start: try startImage())
    #expect(!s.canSend)  // no marks
    s.add(box())
    #expect(s.canSend)
    s.active = false
    #expect(!s.canSend)
    s.active = true
    let none = state(start: nil)
    none.add(box())
    #expect(!none.canSend)
  }

  @Test func bothLanguagesHaveEveryWord() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }
}
