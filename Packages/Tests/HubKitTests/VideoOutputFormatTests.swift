import Foundation
import Testing

@testable import HubKit

@Suite("VideoOutputFormat")
struct VideoOutputFormatTests {
  @Test(arguments: [
    ("480p", 640, 480, 640, 512), ("NTSC", 720, 480, 768, 512), ("PAL", 720, 576, 768, 576),
    ("720p", 1280, 720, 1280, 768), ("1080p", 1920, 1080, 1920, 1088), ("2K DCI", 2048, 1080, 2048, 1088),
    ("1440p", 2560, 1440, 2560, 1472), ("4K UHD", 3840, 2160, 3840, 2176), ("4K DCI", 4096, 2160, 4096, 2176),
    ("8K UHD", 7680, 4320, 7680, 4352),
  ])
  func tableRow(name: String, width: Int, height: Int, generatedWidth: Int, generatedHeight: Int) throws {
    let format = try #require(VideoOutputFormat.all.first { $0.name == name })
    #expect(format.width == width && format.height == height)
    #expect(format.generatedWidth == generatedWidth && format.generatedHeight == generatedHeight)
  }

  @Test func tableHasTenFormatsWithUniqueIDs() {
    #expect(VideoOutputFormat.all.count == 10)
    #expect(Set(VideoOutputFormat.all.map(\.id)).count == 10)
  }

  @Test func matchingFindsLandscapeAndPortrait() {
    #expect(VideoOutputFormat.matching(outputWidth: 1920, outputHeight: 1080)?.name == "1080p")
    #expect(VideoOutputFormat.matching(outputWidth: 1080, outputHeight: 1920)?.name == "1080p")
    #expect(VideoOutputFormat.matching(outputWidth: 1000, outputHeight: 1000) == nil)
  }

  @Test func availabilityFollowsTheSizeLimit() {
    let at2048 = Set(VideoOutputFormat.available(sizeLimit: 2048).map(\.name))
    #expect(at2048 == ["480p", "NTSC", "PAL", "720p", "1080p", "2K DCI"])
    #expect(!at2048.contains("1440p"))
    #expect(VideoOutputFormat.available(sizeLimit: 8192).count == VideoOutputFormat.all.count)
  }

  func format(_ name: String) -> VideoOutputFormat { VideoOutputFormat.all.first { $0.name == name }! }

  @Test func applyingAFormatSetsSizeAndTarget() {
    var p = GenerationParameters()
    p.applyVideoFormat(format("720p"))
    #expect(p.width == 1280 && p.height == 768)
    #expect(p.video.outputWidth == 1280 && p.video.outputHeight == 720)
    #expect(p.activeVideoFormat?.name == "720p")
    #expect(p.activeVideoOutput?.width == 1280 && p.activeVideoOutput?.height == 720)
  }

  @Test func applyingNoneClearsTheTargetAndKeepsTheSize() {
    var p = GenerationParameters()
    p.applyVideoFormat(format("1080p"))
    p.applyVideoFormat(nil)
    #expect(p.width == 1920 && p.height == 1088)
    #expect(p.video.outputWidth == nil && p.video.outputHeight == nil)
    #expect(p.activeVideoOutput == nil && p.activeVideoFormat == nil)
  }

  @Test func aManualSizeChangeMakesTheTargetInconsistent() {
    var p = GenerationParameters()
    p.applyVideoFormat(format("1080p"))
    p.width = 1280
    #expect(p.activeVideoOutput == nil && p.activeVideoFormat == nil)
    p.width = 1920
    #expect(p.activeVideoOutput != nil)
    p.height = 1024
    #expect(p.activeVideoOutput == nil)
  }

  @Test func noTargetIsNeverActive() {
    #expect(GenerationParameters().activeVideoOutput == nil)
    var p = GenerationParameters()
    p.video.outputWidth = 1920
    #expect(p.activeVideoOutput == nil)
  }

  @Test func swapSwapsTheTargetAndStaysConsistent() {
    var p = GenerationParameters()
    p.applyVideoFormat(format("1080p"))
    p.swapDimensions()
    #expect(p.width == 1088 && p.height == 1920)
    #expect(p.video.outputWidth == 1080 && p.video.outputHeight == 1920)
    #expect(p.activeVideoOutput?.width == 1080)
    #expect(p.activeVideoFormat?.name == "1080p")
    p.swapDimensions()
    #expect(p.video.outputWidth == 1920 && p.video.outputHeight == 1080)
  }

  @Test func oldVideoParametersLoadWithoutATarget() throws {
    let old = #"{"numFrames":49}"#.data(using: .utf8)!
    let video = try JSONDecoder().decode(VideoParameters.self, from: old)
    #expect(video.numFrames == 49 && video.outputWidth == nil && video.outputHeight == nil)
  }

  @Test func theTargetRoundTrips() throws {
    var p = GenerationParameters()
    p.applyVideoFormat(format("PAL"))
    let back = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(p))
    #expect(back.video.outputWidth == 720 && back.video.outputHeight == 576)
  }
}
