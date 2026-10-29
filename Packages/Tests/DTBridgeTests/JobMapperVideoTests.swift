import CoreGraphics
import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct JobMapperVideoTests {
  func frame() -> CGImage { TestImages.make(width: 8, height: 8)! }

  func completed(frames: Int, audio: [GeneratedAudio] = []) -> GenerationEvent {
    let configuration = DrawThingsConfiguration()
    let request = GenerationRequest(prompt: "p", negativePrompt: "", configuration: configuration)
    let profile = MediaProfile(family: .flux, isVideo: frames > 1, frameRate: 24, audioSampleRate: nil)
    return .completed(
      GenerationResult(
        request: request, images: (0..<frames).map { _ in frame() }, audio: audio, media: profile,
        startedAt: Date(), completedAt: Date()))
  }

  @Test func configurationCarriesVideoFields() {
    var parameters = GenerationParameters()
    parameters.video = VideoParameters(
      numFrames: 124, shiftForAudio: 3, usesSolAttention: true, solAttentionStart: 2, solAttentionTau: 0.5)
    let configuration = JobMapper.configuration(model: "m.ckpt", parameters: parameters)
    #expect(configuration.numFrames == 124)
    #expect(configuration.shiftForAudio == 3)
    #expect(configuration.usesSolAttention)
    #expect(configuration.solAttentionStart == 2)
    #expect(configuration.solAttentionTau == 0.5)
  }

  @Test func imageJobConfigurationIsUnchanged() throws {
    // A video block that differs from the defaults is ignored while the job is a still image.
    var parameters = GenerationParameters()
    parameters.video = VideoParameters(numFrames: 1, shiftForAudio: 7, usesSolAttention: true, solAttentionStart: 9, solAttentionTau: 2)
    let configuration = JobMapper.configuration(model: "m.ckpt", parameters: parameters)
    let plain = JobMapper.configuration(model: "m.ckpt", parameters: GenerationParameters())
    #expect(try configuration.toJSON() == plain.toJSON())
    #expect(configuration.numFrames == DrawThingsConfiguration().numFrames)
    #expect(configuration.shiftForAudio == DrawThingsConfiguration().shiftForAudio)
    #expect(!configuration.usesSolAttention)
    // The same keys as before the change: the base configuration built by hand.
    let expected = DrawThingsConfiguration(
      width: 1024, height: 1024, steps: 8, model: "m.ckpt")
    let json = try #require(JSONSerialization.jsonObject(with: Data(plain.toJSON().utf8)) as? [String: Any])
    let reference = try #require(JSONSerialization.jsonObject(with: Data(expected.toJSON().utf8)) as? [String: Any])
    for key in ["numFrames", "shiftForAudio", "usesSolAttention", "solAttentionStart", "solAttentionTau"] {
      #expect((json[key] as AnyObject).isEqual(reference[key]))
    }
  }

  @Test func completedVideoKeepsEveryFrame() throws {
    let update = try JobMapper.update(
      for: completed(frames: 124), expected: 1, videoFPS: 24, runsLocally: true, requestedFrames: 124)
    guard case .finishedVideo(let video)? = update else { Issue.record("not a video"); return }
    #expect(video.frames.count == 124)
    #expect(video.framesPerSecond == 24)
    #expect(video.audio == nil)
  }

  @Test func completedVideoCarriesTheFirstAudioTrack() throws {
    let audio = GeneratedAudio(channels: [[0.1, 0.2], [0.3, 0.4]], sampleRate: 24000)
    let update = try JobMapper.update(
      for: completed(frames: 3, audio: [audio]), expected: 1, videoFPS: 24, runsLocally: true, requestedFrames: 3)
    guard case .finishedVideo(let video)? = update else { Issue.record("not a video"); return }
    #expect(video.audio == GeneratedAudioTrack(channels: [[0.1, 0.2], [0.3, 0.4]], sampleRate: 24000))
  }

  @Test func singleFrameOnCloudIsAnError() throws {
    #expect(throws: BackendError.videoNotAvailable) {
      try JobMapper.update(for: completed(frames: 1), expected: 1, videoFPS: 24, runsLocally: false, requestedFrames: 56)
    }
    let update = try JobMapper.update(
      for: completed(frames: 1), expected: 1, videoFPS: 24, runsLocally: true, requestedFrames: 56)
    guard case .finishedVideo(let video)? = update else { Issue.record("not a video"); return }
    #expect(video.frames.count == 1)
  }

  @Test func noFramesIsNoImages() {
    #expect(throws: BackendError.noImages) {
      try JobMapper.update(for: completed(frames: 0), expected: 1, videoFPS: 24, runsLocally: true, requestedFrames: 56)
    }
  }

  @Test func imagesOfAVideoJobStayPreviews() throws {
    let update = try JobMapper.update(
      for: .image(frame(), index: 0), expected: 1, videoFPS: 24, runsLocally: true, requestedFrames: 56)
    guard case .preview? = update else { Issue.record("not a preview"); return }
  }

  @Test func secondPassStepsAddToTheFirst() {
    let result = JobMapper.progressSteps(stage: .secondPassSampling(step: 3), steps: 8, hiresFixStrength: 0.7)
    #expect(result.step == 11)
    #expect(result.total == 14)
    let first = JobMapper.progressSteps(stage: .sampling(step: 5), steps: 8, hiresFixStrength: 0.7)
    #expect(first.step == 5)
    #expect(first.total == 14)
    let plain = JobMapper.progressSteps(stage: .sampling(step: 5), steps: 8, hiresFixStrength: nil)
    #expect(plain.step == 5)
    #expect(plain.total == 8)
  }
}
