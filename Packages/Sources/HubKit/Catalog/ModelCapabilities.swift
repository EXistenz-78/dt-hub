/// What a model supports, read from its Draw Things specification (DTBridge). The advanced
/// cards show a field only when the model can use it (spec §6). An unknown model shows all.
public struct ModelCapabilities: Equatable, Sendable {
  /// Guidance embed (FLUX.1 dev, FLUX.2 dev, HiDream, Hunyuan): `guidance_embed`.
  public var guidanceEmbed: Bool
  /// TeaCache: the spec has `tea_cache_coefficients`.
  public var teaCache: Bool
  /// The text encoders it has: CLIP-L, OpenCLIP-G, T5.
  public var clipL: Bool
  public var openClipG: Bool
  public var t5: Bool
  /// T5 is a separate encoder that can be switched off (SD3, HiDream: `t5_encoder`).
  public var optionalT5: Bool
  /// The main text encoder is a CLIP (SD 1.x, 2.x, SDXL, SD3): CLIP skip applies.
  public var clipSkip: Bool
  /// Native size in pixels (`default_scale` × 64); the Hires fix starts here. nil when unknown.
  public var nativeSize: Int?
  /// The spec's `modifier`: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing` (Edit models),
  /// `inpainting`, `depth`… nil when the spec has none.
  public var modifier: String?

  /// Edit and in-context models: the canvas image is the one to modify, and the Moodboard
  /// brings extra references (tab Control spec §2).
  public var isEditModel: Bool {
    guard let modifier else { return false }
    return ["kontext", "kontext_kv", "qwenimage_edit_plus", "editing"].contains(modifier)
  }

  public init(
    guidanceEmbed: Bool, teaCache: Bool, clipL: Bool, openClipG: Bool, t5: Bool,
    optionalT5: Bool, clipSkip: Bool, nativeSize: Int?, modifier: String? = nil
  ) {
    self.guidanceEmbed = guidanceEmbed
    self.teaCache = teaCache
    self.clipL = clipL
    self.openClipG = openClipG
    self.t5 = t5
    self.optionalT5 = optionalT5
    self.clipSkip = clipSkip
    self.nativeSize = nativeSize
    self.modifier = modifier
  }

  /// A model without a specification: everything may apply.
  public static let unknown = ModelCapabilities(
    guidanceEmbed: true, teaCache: true, clipL: true, openClipG: true, t5: true,
    optionalT5: true, clipSkip: true, nativeSize: nil)
}
