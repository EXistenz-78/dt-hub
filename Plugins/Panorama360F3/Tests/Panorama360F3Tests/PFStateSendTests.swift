import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PFStateSendTests {
  @MainActor final class Recorder {
    var bodies: [[String: Any]] = []
    var answer: [String: Any] = ["type": "ok"]
    var contribute: PFContribute { { [self] body in bodies.append(body); return answer } }
  }

  private func ready(images: Int = 2, size: PFSize = PFSize(width: 256, height: 128)) -> (state: PFState, recorder: Recorder, project: URL) {
    let state = PFState(italian: false)
    let project = TestImages.tempFolder()
    state.switchProject(folder: project)
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
    let folder = TestImages.tempFolder()
    state.addImages((0..<images).map { TestImages.png(width: 40, height: 30, in: folder, name: "r\($0).png") })
    state.mutate { $0.size = size }
    return (state, Recorder(), project)
  }

  private func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }

  private func message(_ object: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

  @Test func sendProposesAGuidedPipelineOfTwoPasses() async throws {
    let (state, recorder, _) = ready()
    await state.send(contribute: recorder.contribute)
    #expect(state.error == nil)
    let body = try #require(recorder.bodies.first)
    let pipeline = try #require(body["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true && pipeline["passes"] as? Int == 2)
    #expect((pipeline["estimate"] as? [String: Any])?["preset"] as? String == "PANO F3")
  }

  @Test func sendFailsWithAnErrorWhenAnImageFileIsMissing() async {
    let (state, recorder, project) = ready()
    try? FileManager.default.removeItem(at: project.appendingPathComponent(state.doc.images[0].file))
    await state.send(contribute: recorder.contribute)
    #expect(recorder.bodies.isEmpty)
    #expect(state.error?.contains("r0.png") == true)
  }

  @Test func sendWithNoVisibleImageDoesNothing() async {
    let (state, recorder, _) = ready(images: 0)
    await state.send(contribute: recorder.contribute)
    #expect(recorder.bodies.isEmpty && state.error != nil)
  }

  @Test func sendShowsTheProblemsTheAppReports() async {
    let (state, recorder, _) = ready()
    recorder.answer = ["type": "ok", "problems": ["preset: PANO F3 is not in the menu"]]
    await state.send(contribute: recorder.contribute)
    #expect(state.error?.contains("PANO F3") == true)
  }

  @Test func sessionNextAnswersPassOneThenPassTwo() async throws {
    let (state, recorder, _) = ready()
    await state.send(contribute: recorder.contribute)
    let one = json(await state.sessionNext(message(["type": "session.next", "index": 1, "count": 2])))
    #expect(one["preset"] as? String == "PANO F3" && one["startImage"] == nil)
    let previous = TestImages.writePNG(TestImages.coordinates(width: 256, height: 128), to: TestImages.tempFolder().appendingPathComponent("p.png"))
    let two = json(
      await state.sessionNext(
        message(["type": "session.next", "index": 2, "count": 2, "previous": ["path": previous.path, "width": 256, "height": 128]])))
    #expect(two["preset"] as? String == "PANO F3 Seamfix" && two["startImage"] != nil && two["moodboard"] == nil)
  }

  @Test func sessionEndedSendsTheResultAndOpensTheViewer() async throws {
    let (state, recorder, _) = ready()
    await state.send(contribute: recorder.contribute)
    _ = await state.sessionNext(message(["type": "session.next", "index": 1, "count": 2]))
    let first = TestImages.writePNG(TestImages.coordinates(width: 256, height: 128), to: TestImages.tempFolder().appendingPathComponent("p.png"))
    _ = await state.sessionNext(
      message(["type": "session.next", "index": 2, "count": 2, "previous": ["path": first.path, "width": 256, "height": 128]]))
    let second = TestImages.writePNG(TestImages.coordinates(width: 128, height: 128), to: TestImages.tempFolder().appendingPathComponent("q.png"))
    recorder.bodies = []
    await state.sessionEnded(
      message(["type": "session.end", "reason": "finished", "previous": ["path": second.path, "width": 128, "height": 128]]),
      contribute: recorder.contribute)
    let result = try #require(recorder.bodies.first?["result"] as? [String: Any])
    let path = try #require(result["path"] as? String)
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(TestImages.size(of: URL(fileURLWithPath: path))?.width == 256)
    #expect(state.doc.viewerOpen)
  }

  @Test func aStoppedRunAfterPassOneStillSendsTheRawPanorama() async throws {
    let (state, recorder, _) = ready()
    await state.send(contribute: recorder.contribute)
    _ = await state.sessionNext(message(["type": "session.next", "index": 1, "count": 2]))
    let first = TestImages.writePNG(TestImages.coordinates(width: 256, height: 128), to: TestImages.tempFolder().appendingPathComponent("p.png"))
    _ = await state.sessionNext(
      message(["type": "session.next", "index": 2, "count": 2, "previous": ["path": first.path, "width": 256, "height": 128]]))
    recorder.bodies = []
    await state.sessionEnded(message(["type": "session.end", "reason": "stopped"]), contribute: recorder.contribute)
    #expect(recorder.bodies.first?["result"] != nil)
  }

  @Test func sessionNextAndEndWithNoSessionAreHarmless() async {
    let state = PFState(italian: false)
    let answer = json(await state.sessionNext(message(["type": "session.next", "index": 1, "count": 2])))
    #expect(answer["done"] as? Bool == true)
    let recorder = Recorder()
    await state.sessionEnded(message(["type": "session.end", "reason": "finished"]), contribute: recorder.contribute)
    #expect(recorder.bodies.isEmpty)
  }
}
