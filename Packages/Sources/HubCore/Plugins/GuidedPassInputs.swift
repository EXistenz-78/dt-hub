import CoreGraphics
import Foundation
import HubKit

/// Why a pass a plug-in handed over cannot run.
public enum GuidedPassError: Error, Equatable, Sendable {
  /// The pass has no size, or the start image it names cannot be read.
  case imageUnreadable
  case imageSize(expected: PipelineSize, got: PipelineSize)
  case maskUnreadable
  case maskSize(expected: PipelineSize, got: PipelineSize)
  /// The pass has a mask but no start image: a mask belongs to the picture it covers.
  case maskWithoutImage
}

/// The inputs of a pass of a pipeline the plug-in guides: its own start image and mask, 1:1 on the size of the pass (no
/// reframing, so a tile and the picture it came from line up to the pixel), and its own Moodboard. A pass with no start
/// image draws on an empty canvas of its size. The Control tab's picture, mask and Moodboard are not used.
public enum GuidedPassInputs {
  /// Longest side read back from a pass's files (a tile is at most 2048).
  static let maxPixel = 4096

  /// What a guided pass starts from: the Generation tab's fields without its LoRAs (a tile gets exactly the LoRAs the pass
  /// names) and with one picture per run (a tab set to make four would make four of every tile), at the size of the pass.
  /// The preset and the fields of the pass go on top of this.
  public static func baseFields(from tab: GenerationFields, size: PipelineSize?) -> GenerationFields {
    var fields = tab
    fields.parameters.loras = []
    fields.parameters.batchSize = 1
    fields.parameters.batchCount = 1
    if let size {
      fields.parameters.width = size.width
      fields.parameters.height = size.height
    }
    return fields
  }

  /// The mask file is a grey PNG the size of the pass, 255 where the model regenerates (`MaskBitmap`); what Draw Things
  /// gets is transparent where it regenerates and opaque where it keeps (`GenerationInputs.mask`). A pass with no
  /// mask regenerates the whole picture (`mask` nil). A pass with no start image (`image` nil) has an empty canvas of
  /// the size of the pass, and cannot have a mask. The Moodboard of the pass becomes the hints in the order given (a
  /// picture that cannot be read is left out, as in any pipeline); `usesMoodboard` is false for models that do not read it.
  public static func inputs(
    for step: PipelineStep, enableInpainting: Bool, usesMoodboard: Bool = true
  ) -> Result<GenerationInputs, GuidedPassError> {
    guard let size = step.size else { return .failure(.imageUnreadable) }
    let hints = usesMoodboard ? (step.moodboard ?? []).compactMap { PluginImages.hint($0) } : []
    guard let ref = step.startImage else {
      if step.mask != nil { return .failure(.maskWithoutImage) }
      return .success(GenerationInputs(image: nil, hints: hints, mask: nil, enableInpainting: enableInpainting))
    }
    guard let image = PluginImages.image(ref, maxPixel: maxPixel) else { return .failure(.imageUnreadable) }
    guard image.width == size.width, image.height == size.height else {
      return .failure(.imageSize(expected: size, got: PipelineSize(width: image.width, height: image.height)))
    }
    var mask: CGImage?
    if let maskRef = step.mask {
      guard let picture = PluginImages.image(maskRef, maxPixel: maxPixel), let bitmap = MaskBitmap(image: picture) else {
        return .failure(.maskUnreadable)
      }
      guard bitmap.width == size.width, bitmap.height == size.height else {
        return .failure(.maskSize(expected: size, got: PipelineSize(width: bitmap.width, height: bitmap.height)))
      }
      mask = InputComposer.mask(
        bitmap, imageWidth: size.width, imageHeight: size.height, toWidth: size.width, height: size.height,
        framing: Framing())
      if mask == nil { return .failure(.maskUnreadable) }
    }
    return .success(GenerationInputs(image: image, hints: hints, mask: mask, enableInpainting: enableInpainting))
  }
}
