/// The model families that make video. DT Hub does not generate video yet, so the DT+ picker leaves their models out
/// (they stay in the catalog, so a chosen one still runs); take this out when video generation arrives.
public enum VideoFamilies {
  public static let keys: Set<String> = [
    "wan_v2.1_1.3b", "wan_v2.1_14b", "wan_v2.2_5b", "ltx2", "ltx2.3", "hunyuan_video", "svd_i2v", "minimax_h3",
    "longcat_video_avatar_v1.5",
  ]

  public static func contains(_ family: String?) -> Bool {
    family.map { keys.contains($0) } ?? false
  }
}
