import HubKit

/// Which base fields make sense for a model family (spec §6: "una tabella famiglia → campi
/// pertinenti vive in HubCore"). The key is Draw Things' model `version`, e.g. "flux2_9b".
/// An unknown or missing family shows everything: hiding a field the model uses is worse
/// than showing one it ignores.
public struct FamilyTraits: Equatable, Sendable {
  /// Flow-matching models: Shift, "resolution-based" shift and CFG-Zero* apply.
  public let usesShift: Bool
  /// The model reads a negative prompt (it acts only with text guidance above 1).
  public let usesNegativePrompt: Bool

  public init(usesShift: Bool, usesNegativePrompt: Bool) {
    self.usesShift = usesShift
    self.usesNegativePrompt = usesNegativePrompt
  }

  public static let all = FamilyTraits(usesShift: true, usesNegativePrompt: true)

  /// Diffusion models without flow matching: SD 1.x/2.x, SDXL (Kolors, SSD-1B, PixArt use
  /// its version), Kandinsky, Würstchen, SVD.
  static let withoutShift: Set<String> = [
    "v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "pixart",
    "kandinsky2.1", "wurstchen_v3.0_stage_c", "wurstchen_v3.0_stage_b", "svd_i2v",
  ]

  /// Models that take no text to avoid: upscalers (SeedVR2) and image-to-video (SVD).
  static let withoutNegativePrompt: Set<String> = ["seedvr2_3b", "seedvr2_7b", "svd_i2v"]

  public static func of(_ family: String?) -> FamilyTraits {
    guard let family else { return .all }
    return FamilyTraits(
      usesShift: !withoutShift.contains(family),
      usesNegativePrompt: !withoutNegativePrompt.contains(family))
  }
}
