import Testing

@testable import HubKit

struct VideoFamiliesTests {
  @Test func h3FramesFollowSeventeenKPlusFive() throws {
    let h3 = try #require(VideoFamilies.info(for: "minimax_h3"))
    #expect(h3.snap(56) == 56)
    #expect(h3.snap(57) == 56)
    #expect(h3.snap(120) == 124)
    #expect(h3.snap(1) == 5)
    #expect(h3.step(56, by: 1) == 73)
    #expect(h3.step(56, by: -1) == 39)
  }

  @Test func ltxFramesFollowEightKPlusOne() throws {
    let ltx = try #require(VideoFamilies.info(for: "ltx2.3"))
    #expect(ltx.snap(100) == 97)
    #expect(ltx.snap(121) == 121)
    #expect(ltx.step(121, by: 1) == 129)
  }

  @Test func limitsAreHonoured() throws {
    let h3 = try #require(VideoFamilies.info(for: "minimax_h3"))
    let ltx = try #require(VideoFamilies.info(for: "ltx2.3"))
    #expect(h3.maxFrames == 192)
    #expect(ltx.maxFrames == 249)
    #expect(h3.minFrames == 5)
    #expect(ltx.minFrames == 9)
    #expect(h3.snap(10_000) == h3.maxFrames)
    #expect(ltx.snap(10_000) == ltx.maxFrames)
    #expect(h3.step(h3.maxFrames, by: 1) == h3.maxFrames)
    #expect(ltx.step(ltx.minFrames, by: -1) == ltx.minFrames)
  }

  @Test func secondsUseTheFamilyFrameRate() throws {
    let h3 = try #require(VideoFamilies.info(for: "minimax_h3"))
    let ltx = try #require(VideoFamilies.info(for: "ltx2.3"))
    #expect(abs(h3.seconds(forFrames: 124) - 5.1667) < 0.001)
    #expect(abs(ltx.seconds(forFrames: 121) - 4.84) < 0.001)
  }

  @Test func onlyH3AndLTXAreEnabled() {
    #expect(VideoFamilies.isEnabled("minimax_h3"))
    #expect(VideoFamilies.isEnabled("ltx2.3"))
    #expect(!VideoFamilies.isEnabled("wan_v2.2_5b"))
    #expect(VideoFamilies.info(for: "wan_v2.2_5b") == nil)
    #expect(VideoFamilies.isHidden("wan_v2.2_5b"))
    #expect(!VideoFamilies.isHidden("minimax_h3"))
    #expect(!VideoFamilies.isHidden("flux2_9b"))
    #expect(!VideoFamilies.isHidden(nil))
  }

  @Test func theFlagsFollowTheFamily() throws {
    let h3 = try #require(VideoFamilies.info(for: "minimax_h3"))
    let ltx = try #require(VideoFamilies.info(for: "ltx2.3"))
    #expect(h3.usesAudioShift && h3.usesAccelerators && !h3.usesStochasticSampling)
    #expect(!ltx.usesAudioShift && !ltx.usesAccelerators && ltx.usesStochasticSampling)
    #expect(h3.framesPerSecond == 24 && h3.audioSampleRate == 32000)
    #expect(ltx.framesPerSecond == 25 && ltx.audioSampleRate == 48000)
  }
}
