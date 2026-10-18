import CoreGraphics
import Foundation
import HubKit

/// Why a pass a plug-in handed over cannot run.
public enum GuidedPassError: Error, Equatable, Sendable {
  /// The pass has no start image, or its file cannot be read.
  case imageUnreadable
  case imageSize(expected: PipelineSize, got: PipelineSize)
  case maskUnreadable
  case maskSize(expected: PipelineSize, got: PipelineSize)
}

/// The inputs of a pass of a pipeline the plug-in guides: its own start image and mask, 1:1 on the size of the pass (no
/// reframing, so a tile and the picture it came from line up to the pixel). The Control tab's picture, mask and Moodboard
/// are not used.
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
  /// mask regenerates the whole picture (`mask` nil).
  public static func inputs(for step: PipelineStep, enableInpainting: Bool) -> Result<GenerationInputs, GuidedPassError> {
    guard let ref = step.startImage, let size = step.size, let image = PluginImages.image(ref, maxPixel: maxPixel) else {
      return .failure(.imageUnreadable)
    }
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
    return .success(GenerationInputs(image: image, hints: [], mask: mask, enableInpainting: enableInpainting))
  }
}
