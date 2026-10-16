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
  /// The spec's `modifier`: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `qwenimage_edit_2511`, `editing` (Edit
  /// models), `inpainting`, `depth`… always in snake_case (see `normalizedModifier`); nil when the spec has none.
  public var modifier: String?
  /// The spec's `padded_text_encoding_length` (the CU estimate's text length); 0 when the spec has none.
  public var paddedTextEncodingLength: Int
  /// The spec's `is_consistency_model`: such models run without CFG.
  public var isConsistencyModel: Bool
  /// The spec's `mmdit.dual_attention_layers` (SD3 medium 3.5); empty when there are none.
  public var dualAttentionLayers: [Int]

  /// An inpainting model (SD inpainting, FLUX Fill...): Draw Things wants its inpaint control for
  /// the mask. The other models take a mask without it (measured on SD 1.5 and FLUX.2 klein).
  public var needsInpaintControl: Bool { modifier == "inpainting" }

  /// Edit and in-context models: the canvas image is the one to modify, and the Moodboard
  /// brings extra references (tab Control spec §2).
  public var isEditModel: Bool {
    guard let modifier else { return false }
    return ["kontext", "kontext_kv", "qwenimage_edit_plus", "qwenimage_edit_2511", "editing"].contains(modifier)
  }

  public init(
    guidanceEmbed: Bool, teaCache: Bool, clipL: Bool, openClipG: Bool, t5: Bool,
    optionalT5: Bool, clipSkip: Bool, nativeSize: Int?, modifier: String? = nil,
    paddedTextEncodingLength: Int = 0, isConsistencyModel: Bool = false, dualAttentionLayers: [Int] = []
  ) {
    self.guidanceEmbed = guidanceEmbed
    self.teaCache = teaCache
    self.clipL = clipL
    self.openClipG = openClipG
    self.t5 = t5
    self.optionalT5 = optionalT5
    self.clipSkip = clipSkip
    self.nativeSize = nativeSize
    self.modifier = Self.normalizedModifier(modifier)
    self.paddedTextEncodingLength = paddedTextEncodingLength
    self.isConsistencyModel = isConsistencyModel
    self.dualAttentionLayers = dualAttentionLayers
  }

  /// The Official list of Draw Things writes the modifiers in camelCase (`qwenimageEditPlus`, `qwenimageEdit2511`,
  /// `kontextKv`), the older lists and the server in snake_case (`qwenimage_edit_plus`): the app keeps the snake_case
  /// one. A key without capitals is already in it (`kontext`, `fl2va`, `none`).
  public static func normalizedModifier(_ key: String?) -> String? {
    guard let key, key.contains(where: \.isUppercase) else { return key }
    var result = ""
    var previous: Character?
    for character in key {
      if character.isUppercase {
        if previous != nil { result.append("_") }
        result.append(contentsOf: character.lowercased())
      } else {
        if character.isNumber, let previous, previous.isLetter { result.append("_") }
        result.append(character)
      }
      previous = character
    }
    return result
  }

  /// A model without a specification: everything may apply.
  public static let unknown = ModelCapabilities(
    guidanceEmbed: true, teaCache: true, clipL: true, openClipG: true, t5: true,
    optionalT5: true, clipSkip: true, nativeSize: nil)
}
