import CoreGraphics
import Foundation

/// The video-only parameters of a RUN, with Draw Things' own defaults.
public struct VideoParameters: Equatable, Codable, Sendable {
  /// Frames of the clip; 1 means a still image.
  public var numFrames: Int
  /// Shift of the audio branch (families with `usesAudioShift`).
  public var shiftForAudio: Double
  /// SOL attention accelerator and its start step and tau.
  public var usesSolAttention: Bool
  public var solAttentionStart: Int
  public var solAttentionTau: Double

  public init(
    numFrames: Int = 1, shiftForAudio: Double = 3, usesSolAttention: Bool = false,
    solAttentionStart: Int = 2, solAttentionTau: Double = 0.5
  ) {
    self.numFrames = numFrames
    self.shiftForAudio = shiftForAudio
    self.usesSolAttention = usesSolAttention
    self.solAttentionStart = solAttentionStart
    self.solAttentionTau = solAttentionTau
  }

  public static let `default` = VideoParameters()

  public static let audioShiftRange = 0.1...12.0
  public static let solStartRange = 0...150
  public static let solTauRange = 0.0...4.0

  /// Reads leniently: a missing or unreadable field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let fallback = Self.default
    numFrames = value(.numFrames, fallback.numFrames)
    shiftForAudio = value(.shiftForAudio, fallback.shiftForAudio)
    usesSolAttention = value(.usesSolAttention, fallback.usesSolAttention)
    solAttentionStart = value(.solAttentionStart, fallback.solAttentionStart)
    solAttentionTau = value(.solAttentionTau, fallback.solAttentionTau)
  }

  /// The same parameters forced into the allowed ranges; frames snapped to the family's valid counts when it is known.
  public func clamped(for info: VideoFamilyInfo?) -> VideoParameters {
    var copy = self
    if let info { copy.numFrames = info.snap(numFrames) }
    copy.shiftForAudio = min(max(shiftForAudio, Self.audioShiftRange.lowerBound), Self.audioShiftRange.upperBound)
    copy.solAttentionStart = min(max(solAttentionStart, Self.solStartRange.lowerBound), Self.solStartRange.upperBound)
    copy.solAttentionTau = min(max(solAttentionTau, Self.solTauRange.lowerBound), Self.solTauRange.upperBound)
    return copy
  }
}

/// The sound of a generated video: one array of samples per channel.
public struct GeneratedAudioTrack: Equatable, Sendable {
  public var channels: [[Float]]
  public var sampleRate: Double

  public init(channels: [[Float]], sampleRate: Double) {
    self.channels = channels
    self.sampleRate = sampleRate
  }
}

/// A finished (or interrupted, `isPartial`) clip as the backend returns it.
public struct GeneratedVideo: Sendable {
  public var frames: [CGImage]
  public var audio: GeneratedAudioTrack?
  public var framesPerSecond: Double
  public var isPartial: Bool

  public init(frames: [CGImage], audio: GeneratedAudioTrack?, framesPerSecond: Double, isPartial: Bool = false) {
    self.frames = frames
    self.audio = audio
    self.framesPerSecond = framesPerSecond
    self.isPartial = isPartial
  }
}
