import CoreGraphics
import Foundation
import HubKit

/// The inputs of one pass of a plug-in's pipeline (plug-in design §7): the tab's own inputs, with the start
/// image and the Moodboard the pass asks for put in their place.
public enum PipelineInputs {
  /// Longest side of a Moodboard picture when it is sent (as for the Moodboard of the Control tab).
  static let hintPixels = 1024

  /// `base` is what the tab would send (framed to the pass's canvas). A pass that takes the previous
  /// output, or names its own start image, replaces the start image: framed to the canvas, with no mask (the
  /// mask belongs to the tab's picture). A pass with a Moodboard replaces the Moodboard; a picture that
  /// cannot be read is left out. `usesMoodboard` is false for models that do not read it.
  public static func inputs(
    for step: PipelineStep, base: GenerationInputs, previousOutput: CGImage?, canvasWidth: Int, canvasHeight: Int,
    usesMoodboard: Bool
  ) -> GenerationInputs {
    var result = base
    let replacement: CGImage? =
      step.useOutputAsStart && previousOutput != nil
      ? previousOutput : step.startImage.flatMap { PluginImages.image($0, maxPixel: 4096) }
    if let replacement,
      let framed = InputComposer.frame(replacement, toWidth: canvasWidth, height: canvasHeight, framing: Framing())
    {
      result.image = framed
      result.mask = nil
    }
    if let refs = step.moodboard {
      result.hints = usesMoodboard ? refs.compactMap { PluginImages.hint($0) } : []
    }
    return result
  }
}

/// Pictures a plug-in leaves in its folder.
public enum PluginImages {
  /// The picture at the path, no larger than `maxPixel` on its long side; nil when it cannot be read.
  public static func image(_ ref: PluginImageRef, maxPixel: Int) -> CGImage? {
    PNGImageStore.image(at: URL(fileURLWithPath: ref.path), maxPixel: maxPixel)
  }

  /// A Moodboard picture of a RUN (PNG, long side at most 1024); nil when it cannot be read.
  public static func hint(_ ref: PluginImageRef) -> GenerationHint? {
    guard let image = image(ref, maxPixel: PipelineInputs.hintPixels), let data = ControlStore.pngData(of: image) else {
      return nil
    }
    return GenerationHint(imageData: data, weight: 1)
  }
}
