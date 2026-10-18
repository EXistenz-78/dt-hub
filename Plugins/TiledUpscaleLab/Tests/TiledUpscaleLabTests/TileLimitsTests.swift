import Testing

@testable import TiledUpscaleLab

struct TileLimitsTests {
  @Test func limitsFollowTheSpec() {
    #expect(TileLimits.verdict(width: 16_384, height: 16_384, passes: 10) == .warn)
    #expect(TileLimits.verdict(width: 16_384, height: 16_448, passes: 10) == .refuse)
    #expect(TileLimits.verdict(width: 16_448, height: 64, passes: 1) == .refuse)
    #expect(TileLimits.verdict(width: 2048, height: 2048, passes: 101) == .warn)
    #expect(TileLimits.verdict(width: 2048, height: 2048, passes: 12) == .ok)
    #expect(TileLimits.verdict(width: 10_100, height: 10_100, passes: 12) == .warn)
  }
}
