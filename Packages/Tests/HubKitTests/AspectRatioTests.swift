import Testing

@testable import HubKit

struct AspectRatioTests {
  @Test func presetsAreTheSixRatiosInLandscapeForm() {
    #expect(AspectRatio.presets.map(\.label) == ["1:1", "5:4", "4:3", "3:2", "2:1", "16:9"])
  }

  @Test func applyingARatioKeepsTheLongSideAndTheOrientation() {
    var landscape = GenerationParameters(width: 1024, height: 1024)
    landscape.apply(AspectRatio(width: 16, height: 9))
    #expect(landscape.width == 1024)
    #expect(landscape.height == 576)

    var portrait = GenerationParameters(width: 832, height: 1216)
    portrait.apply(AspectRatio(width: 3, height: 2))
    #expect(portrait.width == 832)
    #expect(portrait.height == 1216)
    portrait.apply(AspectRatio(width: 2, height: 1))
    #expect(portrait.width == 640)  // 1216 ÷ 2 = 608, halfway: rounds up
    #expect(portrait.height == 1216)
  }

  @Test func lockedRatioMovesTheOtherSide() {
    var parameters = GenerationParameters(width: 1024, height: 768)
    parameters.setWidth(1536, keepingRatio: 4.0 / 3.0)
    #expect(parameters.height == 1152)
    parameters.setHeight(576, keepingRatio: 4.0 / 3.0)
    #expect(parameters.width == 768)
  }

  @Test func unlockedSidesMoveAlone() {
    var parameters = GenerationParameters(width: 1024, height: 768)
    parameters.setWidth(1280, keepingRatio: nil)
    #expect(parameters.width == 1280)
    #expect(parameters.height == 768)
  }

  @Test func theLockedSideStaysInRange() {
    var parameters = GenerationParameters(width: 1024, height: 512)
    parameters.setWidth(2048, keepingRatio: 0.25)
    #expect(parameters.height == 2048)
  }
}
