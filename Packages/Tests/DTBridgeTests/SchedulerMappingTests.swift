import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct SchedulerMappingTests {
  @Test func theSchedulerGoesIntoTheConfiguration() throws {
    var parameters = GenerationParameters()
    #expect(JobMapper.configuration(model: "m.ckpt", parameters: parameters).scheduler == 0)
    for scheduler in Scheduler.allCases {
      parameters.scheduler = scheduler
      let configuration = JobMapper.configuration(model: "m.ckpt", parameters: parameters)
      #expect(configuration.scheduler == Int32(scheduler.rawValue))
      // The library builds the FlatBuffer with the field; it must still encode.
      #expect(try !configuration.toFlatBufferData().isEmpty)
    }
  }

  @Test func theSchedulerValuesAreTheOnesTheServerReads() {
    // The Atelier engine: 0 default, then simple, sgm_uniform, normal, karras, exponential, linear_quadratic, beta.
    #expect(Scheduler.allCases.map(\.rawValue) == Array(0...7))
    #expect(Scheduler.allCases.compactMap(\.displayName) == [
      "Simple", "SGM Uniform", "Normal", "Karras", "Exponential", "Linear Quadratic", "Beta",
    ])
  }

  @Test func parametersWithoutASchedulerLoadWithTheSamplersOwn() throws {
    let data = try JSONEncoder().encode(GenerationParameters())
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "scheduler")
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(GenerationParameters.self, from: old).scheduler == .samplerDefault)

    var parameters = GenerationParameters()
    parameters.scheduler = .karras
    let saved = try JSONEncoder().encode(parameters)
    #expect(try JSONDecoder().decode(GenerationParameters.self, from: saved).scheduler == .karras)
  }

  @Test func substepSamplersDoNotUseOne() {
    #expect(!Scheduler.isUsed(by: .eulerASubstep))
    #expect(!Scheduler.isUsed(by: .dpmppSDESubstep))
    #expect(Scheduler.isUsed(by: .uniPCTrailing))
  }
}
