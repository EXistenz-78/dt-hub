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
}
