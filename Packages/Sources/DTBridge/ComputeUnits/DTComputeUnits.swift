import HubKit

/// The compute-unit estimate and limits the app asks for (spec §4): the port of Draw Things' estimate, and the limits
/// of the cloud's echo (`CloudCatalog`).
public final class DTComputeUnits: ComputeUnitsProviding {
  private let cloud: CloudCatalog

  public init(cloud: CloudCatalog = .shared) {
    self.cloud = cloud
  }

  public func estimate(_ inputs: CUInputs) -> Int? { ComputeUnitsEstimator.estimate(inputs) }

  public func limits() async -> CULimits { await cloud.limits() }
}
