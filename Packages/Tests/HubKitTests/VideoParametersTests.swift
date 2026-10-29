import Foundation
import Testing

@testable import HubKit

@Suite("VideoParameters")
struct VideoParametersTests {
  @Test func defaultsMatchDrawThings() {
    let video = VideoParameters.default
    #expect(video.numFrames == 1)
    #expect(video.shiftForAudio == 3)
    #expect(video.usesSolAttention == false)
    #expect(video.solAttentionStart == 2)
    #expect(video.solAttentionTau == 0.5)
  }

  @Test func clampedSnapsFramesToTheFamily() {
    var video = VideoParameters.default
    video.numFrames = 100
    #expect(video.clamped(for: VideoFamilies.info(for: "minimax_h3")).numFrames == 107)
    #expect(video.clamped(for: nil).numFrames == 100)
    video.shiftForAudio = 99
    video.solAttentionTau = -1
    let clamped = video.clamped(for: nil)
    #expect(clamped.shiftForAudio == 12)
    #expect(clamped.solAttentionTau == 0)
  }

  @Test func oldSavedParametersStillLoad() throws {
    let encoded = try JSONEncoder().encode(GenerationParameters())
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "video")
    let params = try JSONDecoder().decode(
      GenerationParameters.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(params.video == .default)

    let jobData = try JSONEncoder().encode(GenerationJob(prompt: "a", model: "m", parameters: GenerationParameters()))
    var jobObject = try #require(try JSONSerialization.jsonObject(with: jobData) as? [String: Any])
    jobObject.removeValue(forKey: "videoFPS")
    let job = try JSONDecoder().decode(
      GenerationJob.self, from: JSONSerialization.data(withJSONObject: jobObject))
    #expect(job.videoFPS == nil)
  }

  @Test func jobKnowsItsDuration() {
    var params = GenerationParameters()
    params.video.numFrames = 124
    let video = GenerationJob(prompt: "a", model: "m", parameters: params, videoFPS: 24)
    #expect(video.isVideo)
    #expect(abs((video.videoSeconds ?? 0) - 5.1667) < 0.001)
    let image = GenerationJob(prompt: "a", model: "m", parameters: params)
    #expect(image.videoSeconds == nil)
    #expect(image.isVideo == false)
  }

  @Test func roundTripKeepsVideoFields() throws {
    var params = GenerationParameters()
    params.video = VideoParameters(numFrames: 107, shiftForAudio: 5, usesSolAttention: true, solAttentionStart: 4, solAttentionTau: 1.5)
    let job = GenerationJob(prompt: "a", model: "m", parameters: params, videoFPS: 24)
    let decoded = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(decoded == job)
    #expect(decoded.videoFPS == 24)
    #expect(decoded.parameters.video.numFrames == 107)
  }
}
