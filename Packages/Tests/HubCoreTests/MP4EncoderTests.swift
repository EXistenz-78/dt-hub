import AVFoundation
import Foundation
import HubKit
import Testing

@testable import HubCore

struct MP4EncoderTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("MP4EncoderTests-\(UUID()).mp4")
  }

  func video(audio: Bool) -> GeneratedVideo {
    let frames = (0..<5).map { _ in testImage(width: 256, height: 144) }
    var track: GeneratedAudioTrack?
    if audio {
      let rate = 32000.0
      let samples = (0..<Int(rate * 0.2)).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate)) * 0.5 }
      track = GeneratedAudioTrack(channels: [samples, samples], sampleRate: rate)
    }
    return GeneratedVideo(frames: frames, audio: track, framesPerSecond: 24)
  }

  @Test func encoderWritesHEVCWithAudio() async throws {
    let url = tempFile()
    try await MP4Encoder.write(video(audio: true), to: url)
    #expect(FileManager.default.fileExists(atPath: url.path))
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 5.0 / 24.0) <= 0.05)
    let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let descriptions = try await videoTrack.load(.formatDescriptions)
    let subtype = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
    #expect(subtype == kCMVideoCodecType_HEVC)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
  }

  @Test func encoderWithoutAudioHasNoAudioTrack() async throws {
    let url = tempFile()
    try await MP4Encoder.write(video(audio: false), to: url)
    let asset = AVURLAsset(url: url)
    #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
  }

  @Test func encoderRejectsEmptyVideo() async throws {
    await #expect(throws: MP4EncoderError.noFrames) {
      try await MP4Encoder.write(GeneratedVideo(frames: [], audio: nil, framesPerSecond: 24), to: tempFile())
    }
  }

  @Test(.timeLimit(.minutes(1))) func writingToAMissingFolderThrowsAndLeavesNothing() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MP4EncoderTests-missing-\(UUID())", isDirectory: true).appendingPathComponent("x.mp4")
    await #expect(throws: MP4EncoderError.self) { try await MP4Encoder.write(video(audio: true), to: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func anAudioTrackWithRateZeroThrowsInsteadOfTrapping() async throws {
    var clip = video(audio: false)
    clip.audio = GeneratedAudioTrack(channels: [[0, 0.1], [0, 0.1]], sampleRate: 0)
    let url = tempFile()
    await #expect(throws: MP4EncoderError.self) { try await MP4Encoder.write(clip, to: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  // MARK: Center crop

  /// 256×192: red strip on the left 8 columns, green strip on the top 6 rows (over red), blue elsewhere.
  func markedImage() -> CGImage {
    let context = CGContext(
      data: nil, width: 256, height: 192, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 192))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 192 - 6, width: 256, height: 6))  // CG origin is bottom-left
    return context.makeImage()!
  }

  func rgb(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
  }

  func naturalSize(_ url: URL) async throws -> CGSize {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    return try await track.load(.naturalSize)
  }

  func clip(_ frame: CGImage) -> GeneratedVideo {
    GeneratedVideo(frames: Array(repeating: frame, count: 5), audio: nil, framesPerSecond: 24)
  }

  @Test func centeredCropRectUsesFlooredOffsets() {
    let rect = MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (240, 180))
    #expect(rect == CGRect(x: 8, y: 6, width: 240, height: 180))
    #expect(
      MP4Encoder.centeredCrop(frameWidth: 1280, frameHeight: 768, target: (1280, 720))
        == CGRect(x: 0, y: 24, width: 1280, height: 720))
  }

  @Test func centeredCropIgnoresTargetsThatDoNotFit() {
    #expect(MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: nil) == nil)
    #expect(MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (300, 100)) == nil)
    // Frames that are not the target's generated size (e.g. upscaled) are never cropped.
    #expect(MP4Encoder.centeredCrop(frameWidth: 512, frameHeight: 384, target: (240, 180)) == nil)
    #expect(MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 256, target: (240, 180)) == nil)
    #expect(MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (200, 200)) == nil)
    #expect(MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (256, 192)) == nil)
  }

  @Test func centeredCropRoundsAnOddTargetDownToEven() {
    #expect(
      MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (241, 181))
        == CGRect(x: 8, y: 6, width: 240, height: 180))
  }

  @Test func croppedFrameStartsAtTheCenterOffset() {
    let rect = MP4Encoder.centeredCrop(frameWidth: 256, frameHeight: 192, target: (240, 180))
    let frame = markedImage()
    // The original corner is green/red; the cropped one starts at (8, 6): blue (sampled 2 px in, away from the edge).
    #expect(rgb(frame, x: 0, y: 0).g > 200 && rgb(frame, x: 0, y: 20).r > 200)
    let cropped = MP4Encoder.cropped(frame, to: rect)
    #expect(cropped.width == 240 && cropped.height == 180)
    let corner = rgb(cropped, x: 2, y: 2)
    #expect(corner.b > 200 && corner.r < 80 && corner.g < 80)  // the blue of the context is about (4, 51, 255)
  }

  @Test func encoderWritesTheCropTargetSize() async throws {
    let url = tempFile()
    try await MP4Encoder.write(clip(markedImage()), to: url, cropTo: (240, 180))
    #expect(try await naturalSize(url) == CGSize(width: 240, height: 180))
  }

  @Test func encodedFramesAreCenterCropped() async throws {
    let url = tempFile()
    try await MP4Encoder.write(clip(markedImage()), to: url, cropTo: (240, 180))
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try await generator.image(at: .zero).image
    #expect(image.width == 240 && image.height == 180)
    // The red strip and the green strip were cropped away: the top-left pixel is blue.
    let corner = rgb(image, x: 2, y: 2)
    #expect(corner.b > corner.r + 80 && corner.b > corner.g + 80)
  }

  @Test func aTargetLargerThanTheFrameKeepsTheFrameSize() async throws {
    let url = tempFile()
    try await MP4Encoder.write(clip(markedImage()), to: url, cropTo: (512, 320))
    #expect(try await naturalSize(url) == CGSize(width: 256, height: 192))
  }

  @Test func aFrameNotAtTheGeneratedSizeIsNotCropped() async throws {
    let url = tempFile()
    // 256×192 frames, target 120×90 (generated size 128×128): no crop.
    try await MP4Encoder.write(clip(markedImage()), to: url, cropTo: (120, 90))
    #expect(try await naturalSize(url) == CGSize(width: 256, height: 192))
  }

  @Test func noCropKeepsTheFrameSize() async throws {
    let url = tempFile()
    try await MP4Encoder.write(clip(markedImage()), to: url)
    #expect(try await naturalSize(url) == CGSize(width: 256, height: 192))
  }
}
