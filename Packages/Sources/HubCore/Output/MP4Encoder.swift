@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import HubKit

public enum MP4EncoderError: Error, Equatable, Sendable {
  case cannotWrite(String)
  case noFrames
}

/// Writes a generated clip as an MP4: HEVC video at the clip's frame rate and, when the clip has sound, an AAC stereo track.
public enum MP4Encoder {
  public static func write(_ video: GeneratedVideo, to url: URL) async throws {
    guard let first = video.frames.first else { throw MP4EncoderError.noFrames }
    let job = try Job(video: video, first: first, url: url)
    try await job.run()
  }

  /// Rounds a side to the nearest even number (the encoder wants even sides), at least 2.
  static func evenSide(_ value: Int) -> Int {
    max(2, (value + 1) / 2 * 2)
  }

  /// One writing: the writer and its inputs live here and are only touched from `queue`, one task at a time.
  private final class Job: @unchecked Sendable {
    let video: GeneratedVideo
    let url: URL
    let width: Int
    let height: Int
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    var audioInput: AVAssetWriterInput?
    let queue = DispatchQueue(label: "DTHub.MP4Encoder")
    let frameDuration: CMTime
    var nextFrame = 0
    var nextAudioSample = 0
    var audioSamples: [Float] = []  // interleaved stereo
    var audioFormat: CMAudioFormatDescription?
    var pending = 0
    var continuation: CheckedContinuation<Void, Error>?
    var failure: Error?

    init(video: GeneratedVideo, first: CGImage, url: URL) throws {
      self.video = video
      self.url = url
      width = MP4Encoder.evenSide(first.width)
      height = MP4Encoder.evenSide(first.height)
      try? FileManager.default.removeItem(at: url)
      do {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      } catch {
        throw MP4EncoderError.cannotWrite(error.localizedDescription)
      }
      let fps = video.framesPerSecond > 0 ? video.framesPerSecond : 24
      frameDuration = CMTime(value: 1000, timescale: CMTimeScale((fps * 1000).rounded()))
      videoInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
          AVVideoCodecKey: AVVideoCodecType.hevc,
          AVVideoWidthKey: width,
          AVVideoHeightKey: height,
        ])
      videoInput.expectsMediaDataInRealTime = false
      adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
          kCVPixelBufferWidthKey as String: width,
          kCVPixelBufferHeightKey as String: height,
        ])
      guard writer.canAdd(videoInput) else { throw MP4EncoderError.cannotWrite("video input not accepted") }
      writer.add(videoInput)

      if let audio = video.audio, let samples = Self.interleavedStereo(audio), !samples.isEmpty {
        var description = AudioStreamBasicDescription(
          mSampleRate: audio.sampleRate, mFormatID: kAudioFormatLinearPCM,
          mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
          mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
          allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
          extensions: nil, formatDescriptionOut: &format)
        let input = AVAssetWriterInput(
          mediaType: .audio,
          outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
          ], sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw MP4EncoderError.cannotWrite("audio input not accepted") }
        writer.add(input)
        audioInput = input
        audioSamples = samples
        audioFormat = format
      }
    }

    /// Planar channels to interleaved stereo (mono is doubled, extra channels are dropped).
    static func interleavedStereo(_ audio: GeneratedAudioTrack) -> [Float]? {
      guard let left = audio.channels.first else { return nil }
      let right = audio.channels.count > 1 ? audio.channels[1] : left
      let count = min(left.count, right.count)
      var out = [Float](repeating: 0, count: count * 2)
      for i in 0..<count {
        out[2 * i] = left[i]
        out[2 * i + 1] = right[i]
      }
      return out
    }

    func run() async throws {
      guard writer.startWriting() else {
        throw MP4EncoderError.cannotWrite(writer.error?.localizedDescription ?? "cannot start writing")
      }
      writer.startSession(atSourceTime: .zero)
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        queue.async {
          self.continuation = continuation
          self.pending = self.audioInput == nil ? 1 : 2
          self.videoInput.requestMediaDataWhenReady(on: self.queue) { self.feedVideo() }
          self.audioInput?.requestMediaDataWhenReady(on: self.queue) { self.feedAudio() }
        }
      }
      await writer.finishWriting()
      if writer.status != .completed {
        throw MP4EncoderError.cannotWrite(writer.error?.localizedDescription ?? "writing did not complete")
      }
    }

    private func inputDone() {
      pending -= 1
      if pending == 0 {
        let continuation = continuation
        self.continuation = nil
        if let failure { continuation?.resume(throwing: failure) } else { continuation?.resume() }
      }
    }

    private func fail(_ message: String) {
      if failure == nil { failure = MP4EncoderError.cannotWrite(message) }
    }

    private func feedVideo() {
      while videoInput.isReadyForMoreMediaData {
        if failure != nil || nextFrame >= video.frames.count || writer.status == .failed {
          if writer.status == .failed { fail(writer.error?.localizedDescription ?? "writer failed") }
          videoInput.markAsFinished()
          inputDone()
          return
        }
        guard let pool = adaptor.pixelBufferPool, let buffer = pixelBuffer(video.frames[nextFrame], pool: pool) else {
          fail("cannot make a pixel buffer for frame \(nextFrame)")
          continue
        }
        let time = CMTimeMultiply(frameDuration, multiplier: Int32(nextFrame))
        if !adaptor.append(buffer, withPresentationTime: time) {
          fail(writer.error?.localizedDescription ?? "cannot append frame \(nextFrame)")
          continue
        }
        nextFrame += 1
      }
    }

    private func feedAudio() {
      guard let input = audioInput, let format = audioFormat else { return }
      let chunk = 4096
      let total = audioSamples.count / 2
      while input.isReadyForMoreMediaData {
        if failure != nil || nextAudioSample >= total || writer.status == .failed {
          if writer.status == .failed { fail(writer.error?.localizedDescription ?? "writer failed") }
          input.markAsFinished()
          inputDone()
          return
        }
        let count = min(chunk, total - nextAudioSample)
        guard let sample = sampleBuffer(start: nextAudioSample, count: count, format: format),
          input.append(sample)
        else {
          fail(writer.error?.localizedDescription ?? "cannot append audio")
          continue
        }
        nextAudioSample += count
      }
    }

    private func sampleBuffer(start: Int, count: Int, format: CMAudioFormatDescription) -> CMSampleBuffer? {
      let rate = video.audio?.sampleRate ?? 44100
      var block: CMBlockBuffer?
      let bytes = count * 8
      guard
        CMBlockBufferCreateWithMemoryBlock(
          allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
          offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
        let block
      else { return nil }
      let copied = audioSamples.withUnsafeBufferPointer { pointer in
        CMBlockBufferReplaceDataBytes(
          with: UnsafeRawPointer(pointer.baseAddress! + start * 2), blockBuffer: block, offsetIntoDestination: 0,
          dataLength: bytes)
      }
      guard copied == noErr else { return nil }
      var sample: CMSampleBuffer?
      let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
        presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
        packetDescriptions: nil, sampleBufferOut: &sample)
      return status == noErr ? sample : nil
    }

    private func pixelBuffer(_ image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
      var buffer: CVPixelBuffer?
      guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
      CVPixelBufferLockBaseAddress(buffer, [])
      defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
      guard
        let context = CGContext(
          data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
      else { return nil }
      context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return buffer
    }
  }
}
