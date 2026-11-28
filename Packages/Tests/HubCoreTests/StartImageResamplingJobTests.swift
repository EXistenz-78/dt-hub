import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// The algorithm that scaled the start image goes with the job, so the Results window can say which one made a picture.
struct StartImageResamplingJobTests {
  let seedvr = CatalogModel(file: "seedvr2_7b_q8p.ckpt", name: "SeedVR2 7B", family: "seedvr2_7b")

  @Test func theComposerPutsTheAlgorithmInEveryJob() {
    let jobs = JobComposer.batches(
      prompt: "", negativePrompt: "", model: seedvr.file, family: seedvr.family, parameters: GenerationParameters(),
      catalog: ModelCatalog(models: [seedvr], loras: [], fileCount: 1), imageStrength: 1, startImageResampling: .mitchell
    ) { 1 }
    #expect(!jobs.isEmpty && jobs.allSatisfy { $0.startImageResampling == .mitchell })
  }

  @Test func theJobKeepsItInItsMetadata() throws {
    var job = GenerationJob(prompt: "", model: seedvr.file, parameters: GenerationParameters(), imageStrength: 1)
    job.startImageResampling = .bSpline
    let back = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(back.startImageResampling == .bSpline)
  }

  @Test func anOldJobHasNone() throws {
    let job = GenerationJob(prompt: "", model: seedvr.file, parameters: GenerationParameters())
    let json = String(decoding: try JSONEncoder().encode(job), as: UTF8.self)
    #expect(!json.contains("startImageResampling"))
    #expect(try JSONDecoder().decode(GenerationJob.self, from: Data(json.utf8)).startImageResampling == nil)
  }

  @Test func theResultsWindowShowsItWithTheStartImage() {
    var job = GenerationJob(prompt: "", model: seedvr.file, parameters: GenerationParameters(), imageStrength: 1)
    job.startImageResampling = .mitchell
    let image = GeneratedImage(image: testImage(), job: job, date: Date(), fileURL: nil, saveError: nil, elapsed: nil)
    let input = ResultInfo(image).sections.first { $0.kind == .input }?.rows ?? []
    #expect(input.contains(ResultInfo.Row(field: .resampling, value: "Mitchell")))
  }
}
