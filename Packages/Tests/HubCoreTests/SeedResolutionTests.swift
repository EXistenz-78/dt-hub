import HubKit
import Testing

@testable import HubCore

struct SeedResolutionTests {
  @Test func drawsARandomSeedAndRecordsIt() {
    let resolved = GenerationParameters(seed: 1, randomSeed: true).resolvedForRun { 4_242 }
    #expect(resolved.seed == 4_242)
    #expect(!resolved.randomSeed)
  }

  @Test func keepsAFixedSeed() {
    let resolved = GenerationParameters(seed: 77, randomSeed: false).resolvedForRun { 1 }
    #expect(resolved.seed == 77)
  }

  @Test func clampsTheParameters() {
    let resolved = GenerationParameters(width: 1000, steps: 0, randomSeed: false).resolvedForRun()
    #expect(resolved.width == 960)
    #expect(resolved.steps == 1)
  }
}
