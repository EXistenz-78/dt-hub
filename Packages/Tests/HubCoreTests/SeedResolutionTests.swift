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
    #expect(resolved.width == 1024)
    #expect(resolved.steps == 1)
  }
}

struct BatchSplitTests {
  @Test func eachBatchIsItsOwnJobWithAFixedSeedCountingUp() {
    let batches = GenerationParameters(seed: 10, randomSeed: false, batchSize: 2, batchCount: 3).batchesForRun { 1 }
    #expect(batches.map(\.seed) == [10, 11, 12])
    #expect(batches.allSatisfy { $0.batchCount == 1 && $0.batchSize == 2 && !$0.randomSeed })
  }

  @Test func aRandomSeedIsDrawnForEachBatch() {
    var next: UInt32 = 100
    let batches = GenerationParameters(randomSeed: true, batchCount: 3).batchesForRun {
      next += 1
      return next
    }
    #expect(batches.map(\.seed) == [101, 102, 103])
  }

  @Test func theFixedSeedWrapsAroundAtTheTop() {
    let batches = GenerationParameters(seed: .max, randomSeed: false, batchCount: 2).batchesForRun { 1 }
    #expect(batches.map(\.seed) == [.max, 0])
  }

  @Test func batchesAreClamped() {
    let batches = GenerationParameters(width: 1000, randomSeed: false, batchCount: 500).batchesForRun { 1 }
    #expect(batches.count == 100)
    #expect(batches[0].width == 1024)
  }
}
