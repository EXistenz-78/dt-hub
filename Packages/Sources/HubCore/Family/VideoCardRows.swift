import HubKit

/// Which rows the Video Settings and Accelerator cards of the Generation tab show for a model.
public struct VideoCardRows: Equatable, Sendable {
  public let info: VideoFamilyInfo?
  public let showsAudioShift: Bool
  public let showsStochasticSampling: Bool
  public let showsAccelerators: Bool

  /// `info` is nil (no video cards at all) unless the model's family is an enabled video family.
  public init(model: CatalogModel?, sampler: Sampler) {
    let info = VideoFamilies.info(for: model?.family)
    self.info = info
    showsAudioShift = info?.usesAudioShift == true
    showsStochasticSampling = info?.usesStochasticSampling == true && (sampler == .tcd || sampler == .tcdTrailing)
    showsAccelerators = info?.usesAccelerators == true
  }

  public var showsVideoCard: Bool { info != nil }
}
