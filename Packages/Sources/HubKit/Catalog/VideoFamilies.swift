/// How a video family counts frames, time and sound, and which controls it uses.
public struct VideoFamilyInfo: Equatable, Sendable {
  public let family: String
  public let framesPerSecond: Double
  public let audioSampleRate: Int
  /// Valid frame counts are `frameStep * k + frameOffset` (H3: 17k + 5, LTX: 8k + 1).
  public let frameStep: Int
  public let frameOffset: Int
  public let minFrames: Int
  public let maxFrames: Int
  public let usesAudioShift: Bool
  public let usesAccelerators: Bool
  public let usesStochasticSampling: Bool

  /// The valid frame count closest to `frames`, inside `minFrames...maxFrames`.
  public func snap(_ frames: Int) -> Int {
    let k = Int(((Double(frames - frameOffset)) / Double(frameStep)).rounded())
    return clamped(k)
  }

  /// The next (`direction` > 0) or previous valid frame count, stopping at the limits.
  public func step(_ frames: Int, by direction: Int) -> Int {
    let k = Int(((Double(frames - frameOffset)) / Double(frameStep)).rounded())
    return clamped(k + (direction >= 0 ? 1 : -1))
  }

  public func seconds(forFrames frames: Int) -> Double {
    Double(frames) / framesPerSecond
  }

  private func clamped(_ k: Int) -> Int {
    let kMin = Int((Double(minFrames - frameOffset) / Double(frameStep)).rounded(.up))
    let kMax = (maxFrames - frameOffset) / frameStep
    return frameStep * min(max(k, kMin), kMax) + frameOffset
  }
}

/// The model families that make video. `keys` lists all of them; `enabled` holds the ones DT Hub can generate with.
/// The DT+ picker leaves out the hidden ones (video but not enabled), though they stay in the catalog.
public enum VideoFamilies {
  public static let keys: Set<String> = [
    "wan_v2.1_1.3b", "wan_v2.1_14b", "wan_v2.2_5b", "ltx2", "ltx2.3", "hunyuan_video", "svd_i2v", "minimax_h3",
    "longcat_video_avatar_v1.5",
  ]

  private static let enabled: [String: VideoFamilyInfo] = [
    "minimax_h3": VideoFamilyInfo(
      family: "minimax_h3", framesPerSecond: 24, audioSampleRate: 32000, frameStep: 17, frameOffset: 5,
      minFrames: 5, maxFrames: 192, usesAudioShift: true, usesAccelerators: true, usesStochasticSampling: false),
    "ltx2.3": VideoFamilyInfo(
      family: "ltx2.3", framesPerSecond: 25, audioSampleRate: 48000, frameStep: 8, frameOffset: 1,
      minFrames: 9, maxFrames: 249, usesAudioShift: false, usesAccelerators: false, usesStochasticSampling: true),
  ]

  /// The parameters of an enabled video family; `nil` for any other.
  public static func info(for family: String?) -> VideoFamilyInfo? {
    family.flatMap { enabled[$0] }
  }

  public static func isEnabled(_ family: String?) -> Bool {
    info(for: family) != nil
  }

  /// A video family DT Hub does not generate with yet.
  public static func isHidden(_ family: String?) -> Bool {
    guard let family else { return false }
    return keys.contains(family) && enabled[family] == nil
  }
}
