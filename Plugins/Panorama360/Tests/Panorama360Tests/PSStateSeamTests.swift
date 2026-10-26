import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@MainActor
@Suite("Seam in the state")
struct PSStateSeamTests {
  func picture(_ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8), name: String = "r.png") -> URL {
    TestImages.file(TestImages.solid(w, h, rgb.0, rgb.1, rgb.2), in: TestImages.tempFolder(), name: name, type: "public.png")
  }

  func context(_ url: URL?) -> Data {
    let last = url.map { #","lastResult":{"path":"\#($0.path)","name":"\#($0.lastPathComponent)"}"# } ?? ""
    return Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"\#(last)}"#.utf8)
  }

  func state(result: URL?) -> PSState {
    let state = PSState(italian: false)
    state.switchProject(folder: TestImages.tempFolder())
    state.apply(context: context(result))
    return state
  }

  func send() -> (PSContribute, () -> [[String: Any]]) {
    nonisolated(unsafe) var bodies: [[String: Any]] = []
    let contribute: PSContribute = { body in
      bodies.append(body)
      return ["type": "ok"]
    }
    return (contribute, { bodies })
  }

  func endMessage(_ reason: String, previous: URL?, size: Int = 512) -> Data {
    let box = previous.map { #","previous":{"path":"\#($0.path)","width":\#(size),"height":\#(size)}"# } ?? ""
    return Data(#"{"type":"session.end","reason":"\#(reason)"\#(box)}"#.utf8)
  }

  @Test func theButtonIsOffWithoutAResultAndSaysWhy() {
    #expect(state(result: nil).seamReason == .noResult)
    #expect(state(result: URL(fileURLWithPath: "/nowhere/gone.png")).seamReason == .unreadable)
    #expect(state(result: picture(1000, 1024, (1, 2, 3))).seamReason == .notTwoToOne)
    #expect(state(result: picture(1000, 500, (1, 2, 3))).seamReason == .heightNotMultipleOf64)
    #expect(state(result: picture(1024, 512, (1, 2, 3))).seamReason == nil)
  }

  @Test func aResultThatIsTooBigIsRefusedBeforeItIsLoaded() {
    let big = picture(64, 32, (1, 2, 3), name: "big.png")
    let state = state(result: big)
    state.imageSizeReader = { _ in (6144, 3072) }
    #expect(state.seamReason == .tooBig)
  }

  @Test func prepareDeclaresAOnePassGuidedPipeline() async throws {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    let pipeline = try #require(bodies().first?["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true && pipeline["passes"] as? Int == 1 && pipeline["name"] is String)
    let estimate = try #require(pipeline["estimate"] as? [String: Any])
    #expect(estimate["preset"] as? String == "PANO Test")
    #expect((estimate["size"] as? [String: Any])?["width"] as? Int == 512)
    #expect(state.isSeamPrepared && state.error == nil && state.notice != nil)
  }

  @Test func aButtonThatIsOffDeclaresNothingAndSaysWhy() async {
    let state = state(result: nil)
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    #expect(bodies().isEmpty && state.error != nil && !state.isSeamPrepared)
  }

  @Test func aRefusedDeclarationShowsTheErrorAndKeepsNoSession() async {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    await state.prepareSeamCorrection { _ in ["type": "error", "text": "a pipeline is running"] }
    #expect(state.error == "a pipeline is running" && !state.isSeamPrepared)
    #expect(state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8)).isDone)
  }

  @Test func sessionNextAnswersThePassThenDone() async throws {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    await state.prepareSeamCorrection(contribute: send().0)
    let first = try #require(try JSONSerialization.jsonObject(with: state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))) as? [String: Any])
    #expect(first["startImage"] != nil && first["mask"] != nil && first["preset"] as? String == "PANO Test")
    #expect(state.seamNext(Data(#"{"type":"session.next","index":2,"count":1}"#.utf8)).isDone)
  }

  @Test func sessionNextWithoutASessionOrWithJunkIsDone() {
    let state = PSState(italian: false)
    #expect(state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8)).isDone)
    #expect(state.seamNext(Data("nonsense".utf8)).isDone)
  }

  @Test func sessionEndFinishedSendsTheMontageToTheResultsOnce() async throws {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    _ = state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    let generated = picture(512, 512, (0, 0, 255), name: "g.png")
    await state.seamEnded(endMessage("finished", previous: generated), contribute: contribute)
    let result = try #require(bodies().last?["result"] as? [String: Any])
    let path = try #require(result["path"] as? String)
    let size = try #require(PSCutout.pixelSize(of: URL(fileURLWithPath: path)))
    #expect(size.width == 1024 && size.height == 512)
    #expect((result["description"] as? String)?.contains("256") == true, "the band width")
    #expect(state.error == nil && state.notice != nil && !state.isSeamPrepared)
    let sent = bodies().count
    await state.seamEnded(endMessage("finished", previous: generated), contribute: contribute)
    #expect(bodies().count == sent, "a second end does nothing")
  }

  @Test func sessionEndStoppedOrFailedSendsNothingAndSaysSo() async {
    for reason in ["stopped", "failed", "closed"] {
      let state = state(result: picture(1024, 512, (200, 30, 30)))
      let (contribute, bodies) = send()
      await state.prepareSeamCorrection(contribute: contribute)
      let declared = bodies().count
      await state.seamEnded(endMessage(reason, previous: nil), contribute: contribute)
      #expect(bodies().count == declared, "\(reason): nothing sent")
      #expect(state.error != nil || state.notice != nil)
      #expect(!state.isSeamPrepared)
    }
  }

  @Test func aFinishedRunWithoutThePictureIsToldAndSendsNothing() async {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    let declared = bodies().count
    await state.seamEnded(endMessage("finished", previous: nil), contribute: contribute)
    #expect(bodies().count == declared && state.error != nil)
  }

  @Test func thePanoramaIsTheOneLoadedAtThePress() async throws {
    let state = state(result: picture(1024, 512, (200, 30, 30)))  // red
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    state.apply(context: context(picture(1024, 512, (30, 30, 200), name: "other.png")))  // another result arrives: blue
    _ = state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    await state.seamEnded(endMessage("finished", previous: picture(512, 512, (0, 255, 0), name: "g.png")), contribute: contribute)
    let path = try #require(((bodies().last?["result"]) as? [String: Any])?["path"] as? String)
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let outside = TestImages.pixel(image, 300, 100)
    #expect(outside.r > 150 && outside.b < 60, "the part outside the band is the old (red) panorama: \(outside)")
  }

  @Test func theMontageSurvivesAProjectSwitchAndIsStillSent() async throws {
    let state = state(result: picture(1024, 512, (200, 30, 30)))
    let (contribute, bodies) = send()
    await state.prepareSeamCorrection(contribute: contribute)
    _ = state.seamNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    state.switchProject(folder: TestImages.tempFolder())
    await state.seamEnded(endMessage("finished", previous: picture(512, 512, (0, 255, 0), name: "g.png")), contribute: contribute)
    #expect(bodies().last?["result"] != nil, "the app files it under the project that is open now")
  }
}

extension Data {
  var isDone: Bool { ((try? JSONSerialization.jsonObject(with: self)) as? [String: Any])?["done"] as? Bool == true }
}
