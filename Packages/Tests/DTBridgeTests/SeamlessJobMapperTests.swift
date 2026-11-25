import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct SeamlessJobMapperTests {
  /// A typical job: the base parameters, a LoRA, a negative prompt.
  static func typicalJob() -> GenerationJob {
    let parameters = GenerationParameters(
      width: 832, height: 1216, steps: 20, guidanceScale: 4, sampler: .ddimTrailing, shift: 3,
      seed: 42, randomSeed: false, batchSize: 1, batchCount: 2)
    return GenerationJob(
      prompt: "a lighthouse", negativePrompt: "blurry", model: "flux_2_klein_9b_f16.ckpt", parameters: parameters)
  }

  static func bytes(of job: GenerationJob) throws -> Data {
    try JobMapper.request(for: job).configuration.toFlatBufferData()
  }

  /// The FlatBuffers bytes of `typicalJob()` captured BEFORE the seamless field existed.
  static let capturedBefore = "bAAAAGgAPAAAADoAOAA0ADAALAAoACQAIwAcAAAAAAAAAAAAAAAAAAAAGwAAABQAEAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAaAAAAAAAQECamVk/AADAPywAAAAsAAAAAAAAAgIAAAAAAAAQIAAAAAAAgD8AAIBAFAAAACoAAAATAA0AAAAAAAAAAAAYAAAAZmx1eF8yX2tsZWluXzliX2YxNi5ja3B0AAAAAA=="

  @Test func aJobWithoutSeamlessEncodesTheSameBytesAsBefore() throws {
    let now = try Self.bytes(of: Self.typicalJob()).base64EncodedString()
    
    #expect(now == Self.capturedBefore)
  }
}
