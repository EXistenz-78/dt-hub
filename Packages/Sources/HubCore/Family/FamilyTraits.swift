import HubKit

/// Which base fields make sense for a model family (spec §6: "una tabella famiglia → campi
/// pertinenti vive in HubCore"). The key is Draw Things' model `version`, e.g. "flux2_9b".
/// An unknown or missing family shows everything: hiding a field the model uses is worse
/// than showing one it ignores.
public struct FamilyTraits: Equatable, Sendable {
  /// Flow-matching models: Shift, "resolution-based" shift and CFG-Zero* apply.
  public let usesShift: Bool
  /// The model reads a negative prompt (it acts only with text guidance above 1). From the family's Family prompt.
  public let usesNegativePrompt: Bool
  /// The Moodboard works without an adapter: the modern families read their references themselves.
  /// False for the old families that would need an IP-Adapter or a ControlNet (tab Control spec §3).
  public let usesMoodboard: Bool

  public init(usesShift: Bool, usesNegativePrompt: Bool, usesMoodboard: Bool = true) {
    self.usesShift = usesShift
    self.usesNegativePrompt = usesNegativePrompt
    self.usesMoodboard = usesMoodboard
  }

  public static let all = FamilyTraits(usesShift: true, usesNegativePrompt: true)

  /// Diffusion models without flow matching: SD 1.x/2.x, SDXL (Kolors, SSD-1B, PixArt use
  /// its version), Kandinsky, Würstchen, SVD.
  static let withoutShift: Set<String> = [
    "v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "pixart",
    "kandinsky2.1", "wurstchen_v3.0_stage_c", "wurstchen_v3.0_stage_b", "svd_i2v",
  ]

  /// Families that do not read the Moodboard. SD 1.x/2.x, SDXL and SSD-1B would need a control
  /// model they do not have here; Z Image was measured: its result is the same with and without
  /// a Moodboard picture (1 October 2026). The models that read it (FLUX.2, Qwen Image 2.1…) are
  /// not listed, and neither is a new or unknown family: hiding what a model uses is worse than
  /// showing what it ignores. Update this list as families are tried.
  static let withoutMoodboard: Set<String> = ["v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "z_image"]

  /// Models that take no text to avoid and have no Family prompt: upscalers (SeedVR2) and image-to-video (SVD).
  static let withoutNegativePrompt: Set<String> = ["seedvr2_3b", "seedvr2_7b", "svd_i2v"]

  /// What the built-in Family prompts say (header `negative: true|false`): the one place that knows whether a family
  /// reads a negative prompt. A new Family prompt is enough: the field and what RUN sends follow it. Read once.
  /// A family with no Family prompt yet is not here and keeps the field (hiding what a model uses is worse).
  private static let negativeByFamilyPrompt: [String: Bool] = {
    Dictionary(PromptLibrary.builtIn.families().map { ($0.id, $0.negative) }, uniquingKeysWith: { first, _ in first })
  }()

  private static func usesNegativePrompt(_ family: String) -> Bool {
    if withoutNegativePrompt.contains(family) { return false }
    return negativeByFamilyPrompt[PromptLibrary.aliases[family] ?? family] ?? true
  }

  public static func of(_ family: String?) -> FamilyTraits {
    guard let family else { return .all }
    return FamilyTraits(
      usesShift: !withoutShift.contains(family),
      usesNegativePrompt: usesNegativePrompt(family),
      usesMoodboard: !withoutMoodboard.contains(family))
  }
}
