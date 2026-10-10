import Foundation
import Testing

@testable import HubKit

struct TiledSizesTests {
  func parameters(_ width: Int, _ height: Int, tiled: Bool) -> GenerationParameters {
    var parameters = GenerationParameters(width: width, height: height)
    parameters.advanced.tiledDiffusion = tiled
    return parameters
  }

  @Test func theLimitFollowsTheTiledDiffusion() {
    #expect(parameters(1024, 1024, tiled: false).sizeLimit == 2048)
    #expect(parameters(1024, 1024, tiled: true).sizeLimit == 8192)
    #expect(GenerationParameters.tiledSizeRange == 64...8192)
  }

  @Test func snapStopsAtTheLimitItIsGiven() {
    #expect(GenerationParameters.snap(5000) == 2048)
    #expect(GenerationParameters.snap(5000, limit: 8192) == 4992)
    #expect(GenerationParameters.snap(9000, limit: 8192) == 8192)
    #expect(GenerationParameters.snap(10, limit: 8192) == 64)
  }

  @Test func clampedKeepsWhatTheLimitAllows() {
    let tiled = parameters(4096, 3000, tiled: true).clamped()
    #expect(tiled.width == 4096 && tiled.height == 3008)
    let plain = parameters(4096, 3000, tiled: false).clamped()
    #expect(plain.width == 2048 && plain.height == 2048)
    let huge = parameters(9999, 20_000, tiled: true).clamped()
    #expect(huge.width == 8192 && huge.height == 8192)
  }

  @Test func aLockedRatioAndTheRatioPresetsReachTheLimit() {
    var tiled = parameters(4096, 2048, tiled: true)
    tiled.setWidth(6000, keepingRatio: 2)
    #expect(tiled.height == 3008)
    var plain = parameters(1024, 512, tiled: false)
    plain.setWidth(4000, keepingRatio: 2)
    #expect(plain.height == 1984)  // 4000 / 2 = 2000, snapped to 1984
    var preset = parameters(8192, 8192, tiled: true)
    preset.apply(AspectRatio(width: 16, height: 9))
    #expect(preset.width == 8192 && preset.height == 4608)
  }

  @Test func fittingKeepsTheRatioAndTheLongSideIsTheLimit() {
    func fitted(_ width: Int, _ height: Int) -> (Int, Int) {
      var p = parameters(width, height, tiled: false)
      p.fitSizeToLimit()
      return (p.width, p.height)
    }
    #expect(fitted(4096, 2048) == (2048, 1024))
    #expect(fitted(8192, 4096) == (2048, 1024))
    #expect(fitted(4000, 3000) == (2048, 1536))
    #expect(fitted(3000, 4000) == (1536, 2048))
    #expect(fitted(8192, 64) == (2048, 64))  // the short side never goes under 64
    #expect(fitted(2048, 1024) == (2048, 1024))  // already within
    var tiled = parameters(8192, 4096, tiled: true)
    tiled.fitSizeToLimit()
    #expect(tiled.width == 8192 && tiled.height == 4096)
  }

  @Test func turningTheTiledDiffusionOffBringsTheSizeBack() {
    var parameters = parameters(4096, 2048, tiled: true)
    parameters.setTiledDiffusion(false)
    #expect(parameters.advanced.tiledDiffusion == false)
    #expect(parameters.width == 2048 && parameters.height == 1024)
  }

  @Test func turningItOnLeavesTheSizeAlone() {
    var parameters = parameters(1024, 512, tiled: false)
    parameters.setTiledDiffusion(true)
    #expect(parameters.advanced.tiledDiffusion)
    #expect(parameters.width == 1024 && parameters.height == 512)
  }

  @Test func aSavedSessionReadsWithTheLimitOfItsOwnSwitch() throws {
    let big = Data(#"{"width": 4096, "height": 2048, "advanced": {"tiledDiffusion": true}}"#.utf8)
    let kept = try JSONDecoder().decode(GenerationParameters.self, from: big).clamped()
    #expect(kept.width == 4096 && kept.height == 2048)
    let plain = Data(#"{"width": 4096, "height": 2048}"#.utf8)
    let limited = try JSONDecoder().decode(GenerationParameters.self, from: plain).clamped()
    #expect(limited.width == 2048 && limited.height == 2048)
  }

  // MARK: HiRes (beta), by hand

  @Test func hiResByHandAllowsTheBigSizesWithoutTheTiledDiffusion() {
    var p = parameters(1024, 1024, tiled: false)
    #expect(p.isHighRes == false && p.sizeLimit == 2048)
    p.setHighRes(true)
    #expect(p.isHighRes && p.sizeLimit == 8192 && p.advanced.tiledDiffusion == false)
    p.width = 2816
    p.height = 2816
    let sent = p.clamped()
    #expect(sent.width == 2816 && sent.height == 2816)
  }

  @Test func theTiledDiffusionTurnsHiResOnByItself() {
    #expect(parameters(1024, 1024, tiled: true).isHighRes)
    #expect(parameters(1024, 1024, tiled: true).highRes == false)  // derived, not stored
  }

  @Test func turningHiResOffBringsTheSizeBack() {
    var p = parameters(4096, 2048, tiled: false)
    p.highRes = true
    p.setHighRes(false)
    #expect(p.width == 2048 && p.height == 1024)
  }

  @Test func hiResByHandSurvivesTheTiledDiffusionBeingTurnedOff() {
    var p = parameters(4096, 2048, tiled: true)
    p.highRes = true
    p.setTiledDiffusion(false)
    #expect(p.width == 4096 && p.height == 2048 && p.sizeLimit == 8192)
  }

  @Test func hiResIsSavedAndOldFilesReadWithItOff() throws {
    var p = GenerationParameters(width: 4096, height: 2048)
    p.highRes = true
    let back = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(p))
    #expect(back.highRes && back.clamped().width == 4096)
    let old = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"width": 4096}"#.utf8))
    #expect(old.highRes == false && old.clamped().width == 2048)
  }
}
