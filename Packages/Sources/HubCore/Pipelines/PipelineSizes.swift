import HubKit

/// The sizes of the passes of a user's pipeline (`2026-10-12-pipeline-di-preset-utente-design.md` §5): the first
/// pass has the tab's size, each other pass the size of the one before it multiplied by its scale.
public enum PipelineSizes {
  /// `size` × `scale`, in multiples of 64. When the long side would pass `limit` both sides shrink by the same
  /// factor first, so the ratio stays.
  public static func scaled(_ size: Size, by scale: Double, limit: Int) -> Size {
    var width = Double(size.width) * scale
    var height = Double(size.height) * scale
    let long = max(width, height)
    if long > Double(limit) {
      width *= Double(limit) / long
      height *= Double(limit) / long
    }
    return Size(
      width: GenerationParameters.snap(width, limit: limit), height: GenerationParameters.snap(height, limit: limit))
  }

  /// One size per pass; `limits` are the largest sides the passes allow (2048, or 8192 with HiRes or the Tiled
  /// Diffusion). `scales[0]` is ignored: the first pass is `first`, brought within its limit.
  public static func sizes(first: Size, scales: [Double], limits: [Int]) -> [Size] {
    var result: [Size] = []
    for (index, limit) in limits.enumerated() {
      let scale = index == 0 || index >= scales.count ? 1 : scales[index]
      result.append(scaled(result.last ?? first, by: scale, limit: limit))
    }
    return result
  }
}
