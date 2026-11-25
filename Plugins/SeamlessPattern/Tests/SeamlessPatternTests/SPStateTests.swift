import CoreGraphics
import Foundation
import Testing

@testable import SeamlessPattern

@MainActor
@Suite("SPState")
struct SPStateTests {
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sp-state-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A state whose sent messages are kept; `answer` is what the app says to each.
  private final class Wire: @unchecked Sendable {
    var sent: [Data] = []
    var answer: [String: Any]? = ["type": "ok", "conflicts": 0, "problems": [String]()]
  }

  private func make(_ wire: Wire = Wire(), store: SPStore = SPStore()) -> SPState {
    let state = SPState(store: store)
    state.send = { data in
      wire.sent.append(data)
      return wire.answer
    }
    return state
  }

  private func json(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private func ready(_ state: SPState, family: String = "krea_2") async {
    await state.applyContext(family: family, customServer: true, lastResultPath: nil)
  }

  private func writePNG(_ image: CGImage) -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sp-\(UUID().uuidString).png")
    try? SPPNG.data(from: image)?.write(to: url)
    return url.path
  }

  @Test func prepareSendsThePipelineAndMarksItPrepared() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    #expect(state.isPrepared)
    #expect(wire.sent == [SPSender.prepare(mode: .both)])
  }

  @Test func changingTheModeWhilePreparedSendsItAgain() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    await state.setMode(.upDown)
    #expect(wire.sent.count == 2)
    #expect(wire.sent.last == SPSender.prepare(mode: .upDown))
    #expect(state.isPrepared)
  }

  @Test func changingTheModeWhenNotPreparedSendsNothing() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.setMode(.leftRight)
    #expect(wire.sent.isEmpty)
    #expect(state.mode == .leftRight)
  }

  @Test func stopWithdrawsAndClearsThePreparedFlag() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    await state.stop()
    #expect(!state.isPrepared)
    #expect(wire.sent.last == SPSender.stop())
  }

  @Test func withoutTheCustomServerThereIsOnlyTheWarning() async {
    let wire = Wire()
    let state = make(wire)
    await state.applyContext(family: "krea_2", customServer: false, lastResultPath: nil)
    #expect(!state.canPrepare)
    #expect(state.warning == "Seamless Pattern needs DT Hub's own server (Preferences › Draw Things: use the included server).")
    await state.prepare()
    #expect(wire.sent.isEmpty && !state.isPrepared)
  }

  @Test func anOldAppWithoutCustomServerIsTheSame() async {
    let state = make()
    await state.applyContext(family: "krea_2", customServer: nil, lastResultPath: nil)
    #expect(!state.canPrepare)
    #expect(state.warning == SPState.customServerWarning)
  }

  @Test func aFamilyOutsideTheListCannotPrepare() async {
    let state = make()
    await state.applyContext(family: "sdxl", customServer: true, lastResultPath: nil)
    #expect(!state.canPrepare)
    #expect(state.warning == nil)
  }

  @Test func theServerGoingAwayWhilePreparedWithdraws() async {
    for gone in [false, nil] as [Bool?] {
      let wire = Wire()
      let state = make(wire)
      await ready(state)
      await state.prepare()
      await state.applyContext(family: "krea_2", customServer: gone, lastResultPath: nil)
      #expect(!state.isPrepared)
      #expect(wire.sent.last == SPSender.stop())
    }
  }

  @Test func aFamilyChangeToAnUnsupportedOneWhilePreparedWithdraws() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    await state.applyContext(family: "sdxl", customServer: true, lastResultPath: nil)
    #expect(!state.isPrepared)
    #expect(wire.sent.last == SPSender.stop())
  }

  @Test func aChangeToAnotherSupportedFamilyKeepsThePipeline() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    await state.applyContext(family: "z_image", customServer: true, lastResultPath: nil)
    #expect(state.isPrepared)
    #expect(wire.sent.count == 1)
  }

  @Test func theAppsProblemBecomesTheNoticeAndNothingIsPrepared() async {
    let wire = Wire()
    wire.answer = ["type": "ok", "conflicts": 0, "problems": ["seamless: the custom server is not running."]]
    let state = make(wire)
    await ready(state)
    await state.prepare()
    #expect(state.notice == "seamless: the custom server is not running.")
    #expect(!state.isPrepared)
    wire.answer = ["type": "error", "text": "Plug-in is off."]
    await state.prepare()
    #expect(state.notice == "Plug-in is off.")
    wire.answer = ["type": "ok", "problems": [String]()]
    await state.prepare()
    #expect(state.notice == nil && state.isPrepared)
  }

  @Test func noAnswerIsNotPrepared() async {
    let wire = Wire()
    wire.answer = nil
    let state = make(wire)
    await ready(state)
    await state.prepare()
    #expect(!state.isPrepared)
    #expect(state.notice != nil)
  }

  @Test func aNewLastResultRecomputesTheSeam() async throws {
    let state = make()
    let smooth = TestImages.make(128, 128) { x, y, _ in (x + y) / 2 }
    let broken = TestImages.make(128, 128) { x, _, _ in x < 64 ? 0 : 255 }
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: writePNG(smooth))
    #expect(state.seam != nil)
    let first = state.seam?.leftRight
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: writePNG(broken))
    #expect(state.seam?.leftRight != first)
    #expect(state.source != nil)
  }

  @Test func theSameLastResultDoesNotReplaceADroppedImage() async {
    let state = make()
    let path = writePNG(TestImages.make(128, 128) { x, _, _ in x })
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: path)
    let dropped = writePNG(TestImages.make(96, 96) { _, y, _ in y })
    await state.show(url: URL(fileURLWithPath: dropped))
    #expect(state.source?.path == dropped)
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: path)
    #expect(state.source?.path == dropped)
    await state.applyContext(family: "krea_2", customServer: true, lastResultPath: writePNG(TestImages.make(80, 80) { x, _, _ in x }))
    #expect(state.source?.path != dropped)
  }

  @Test func modeAndViewSurviveAProjectSwitch() async {
    let (a, b) = (folder(), folder())
    let state = make()
    state.switchProject(folder: a)
    await state.setMode(.leftRight)
    state.view = .offset
    state.switchProject(folder: b)
    #expect(state.mode == .both && state.view == .tile)
    state.switchProject(folder: a)
    #expect(state.mode == .leftRight && state.view == .offset)
  }

  @Test func deactivatingForgetsThePreparedFlagWithoutSending() async {
    let wire = Wire()
    let state = make(wire)
    await ready(state)
    await state.prepare()
    state.deactivate()
    #expect(!state.isPrepared)
    #expect(wire.sent.count == 1)
  }

  @Test func theSeamLineJudgesOnlyTheRequestedDirections() {
    let pass = SPSeamResult(status: .pass, ratio: 1.02, rank: 0.5, vsWorst: 0.7)
    #expect(SPState.seamText(pass, judged: true) == "PASS")
    #expect(SPState.seamText(pass, judged: false) == "1.02")
    #expect(SPState.seamText(SPSeamResult(status: .fail, ratio: 9, rank: 0, vsWorst: 3), judged: true) == "FAIL")
    #expect(SPState.seamText(SPSeamResult(status: .warn, ratio: 3, rank: 0, vsWorst: 1.1), judged: true) == "WARN")
    #expect(SPState.seamText(SPSeamResult(status: .notApplicable, ratio: nil, rank: nil, vsWorst: nil), judged: true) == "N/A")
    #expect(SPState.seamText(SPSeamResult(status: .notApplicable, ratio: nil, rank: nil, vsWorst: nil), judged: false) == "N/A")
    #expect(SPMode.both.judgesLeftRight && SPMode.both.judgesUpDown)
    #expect(SPMode.leftRight.judgesLeftRight && !SPMode.leftRight.judgesUpDown)
    #expect(!SPMode.upDown.judgesLeftRight && SPMode.upDown.judgesUpDown)
  }
}
