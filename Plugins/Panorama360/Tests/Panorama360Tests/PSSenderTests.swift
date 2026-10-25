import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@MainActor
@Suite("Sender")
struct PSSenderTests {
  /// A state in an open project with one visible sticker, and a folder to exchange pictures through.
  func readyState() -> (PSState, temp: URL) {
    let state = PSState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    let temp = TestImages.tempFolder()
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_base_9b_i8x.ckpt","tempFolder":"\#(temp.path)"}"#.utf8))
    let sticker = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [sticker]; $0.description = "a quiet harbour at dawn" }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: sticker.id)
    return (state, temp)
  }

  @MainActor final class Capture {
    var bodies: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok", "conflicts": 0]
    func contribute(_ body: [String: Any]) async -> [String: Any]? {
      bodies.append(body)
      return answer
    }
  }

  @Test func bodyNamesThePresetForTheMode() {
    let url = URL(fileURLWithPath: "/tmp/x.png")
    #expect(PSSender.body(startImage: url, description: "d", mode: .normal)["preset"] as? String == "PAN · 360 ERP")
    #expect(PSSender.body(startImage: url, description: "d", mode: .fast)["preset"] as? String == "PAN · 360 ERP Fast")
  }

  @Test func bodyKeepsTheSizeAt2048x1024AndStrength1() throws {
    let body = PSSender.body(startImage: URL(fileURLWithPath: "/tmp/x.png"), description: "d", mode: .normal)
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(fields["width"] as? Int == 2048 && fields["height"] as? Int == 1024)
    #expect(body["strength"] as? Double == 1)
    let start = try #require(body["startImage"] as? [String: Any])
    #expect(start["path"] as? String == "/tmp/x.png" && start["name"] as? String == "panorama-360.png")
  }

  @Test func thePromptIsOnlyTheDescription() throws {
    let body = PSSender.body(startImage: URL(fileURLWithPath: "/tmp/x.png"), description: "  a quiet harbour at dawn \n", mode: .normal)
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(fields["prompt"] as? String == "a quiet harbour at dawn")
  }

  @Test func anEmptyDescriptionSendsAnEmptyPromptSoTheTabsOldOneIsNotKept() throws {
    let body = PSSender.body(startImage: URL(fileURLWithPath: "/tmp/x.png"), description: "  \n", mode: .normal)
    let fields = try #require(body["fields"] as? [String: Any])
    #expect(fields["prompt"] as? String == "")
  }

  @Test func sendWritesA2048x1024PNGAndContributesOnce() async throws {
    let (state, _) = readyState()
    let capture = Capture()
    await state.send(contribute: capture.contribute)
    #expect(capture.bodies.count == 1 && state.error == nil && state.hasSent)
    let start = try #require(capture.bodies[0]["startImage"] as? [String: Any])
    let path = try #require(start["path"] as? String)
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 2048 && image.height == 1024)
    #expect(TestImages.pixel(image, 1024, 512).r > 150 && TestImages.pixel(image, 5, 5).g == 255)
  }

  @Test func theModeDecidesThePresetOfTheSend() async {
    let (state, _) = readyState()
    state.mutate { $0.mode = .fast }
    let capture = Capture()
    await state.send(contribute: capture.contribute)
    #expect(capture.bodies[0]["preset"] as? String == "PAN · 360 ERP Fast")
  }

  @Test func problemsFromTheAppBecomeTheErrorBox() async {
    let (state, _) = readyState()
    let capture = Capture()
    capture.answer = ["type": "ok", "problems": ["preset: there is no preset named “PAN · 360 ERP”."]]
    await state.send(contribute: capture.contribute)
    #expect(state.error?.contains("PAN · 360 ERP") == true && !state.hasSent)
  }

  @Test func anErrorAnswerAndNoAnswerAreShown() async {
    let (state, _) = readyState()
    let capture = Capture()
    capture.answer = ["type": "error", "text": "The plug-in is not active."]
    await state.send(contribute: capture.contribute)
    #expect(state.error == "The plug-in is not active.")
    capture.answer = nil
    await state.send(contribute: capture.contribute)
    #expect(state.error != nil && state.error != "The plug-in is not active.")
  }

  @Test func sendIsRefusedWithoutVisibleStickers() async {
    let (state, _) = readyState()
    state.update(state.doc.stickers[0].id) { $0.visible = false }
    let capture = Capture()
    await state.send(contribute: capture.contribute)
    #expect(capture.bodies.isEmpty && state.error != nil)
  }

  @Test func sendBeforeAProjectWritesNothing() async throws {
    let state = PSState(italian: false)
    let temp = TestImages.tempFolder()
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(temp.path)"}"#.utf8))
    let sticker = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [sticker] }
    state.setImage(TestImages.solid(60, 40, 200, 50, 50), for: sticker.id)
    let capture = Capture()
    await state.send(contribute: capture.contribute)
    #expect(capture.bodies.isEmpty && state.error != nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path).isEmpty)
  }

  @Test func warningWhenTheModelIsNotBaseAfterTheSend() async {
    let (state, _) = readyState()
    #expect(state.warning == nil)
    await state.send(contribute: Capture().contribute)
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_9b_q8p.ckpt","tempFolder":"/tmp"}"#.utf8))
    #expect(state.warning != nil)
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_base_9b_i8x.ckpt","tempFolder":"/tmp"}"#.utf8))
    #expect(state.warning == nil)
  }
}
