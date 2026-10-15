import Foundation

/// What the compute-unit (CU) estimate of one request needs (CU meter spec §4). Sizes are in pixels.
public struct CUInputs: Equatable, Sendable {
  /// Draw Things model version, e.g. "flux2_9b" (`CatalogModel.family`).
  public var family: String
  public var modelFile: String
  public var capabilities: ModelCapabilities
  public var width: Int
  public var height: Int
  public var steps: Int
  /// The strength of the start image; 1 without one.
  public var strength: Double
  public var guidanceScale: Double
  public var imageGuidanceScale: Double
  public var batchSize: Int
  public var hasImage: Bool
  /// Moodboard (and edit-model) pictures that go with the request.
  public var referenceImages: Int

  public init(
    family: String, modelFile: String, capabilities: ModelCapabilities, width: Int, height: Int, steps: Int,
    strength: Double = 1, guidanceScale: Double = 1, imageGuidanceScale: Double = 1.5, batchSize: Int = 1,
    hasImage: Bool = false, referenceImages: Int = 0
  ) {
    self.family = family
    self.modelFile = modelFile
    self.capabilities = capabilities
    self.width = width
    self.height = height
    self.steps = steps
    self.strength = strength
    self.guidanceScale = guidanceScale
    self.imageGuidanceScale = imageGuidanceScale
    self.batchSize = batchSize
    self.hasImage = hasImage
    self.referenceImages = referenceImages
  }
}

/// The CU a request may use. Draw Things' own defaults (Plus 40 000, community 10 000), unless the cloud's server
/// announces a temporary policy (spec §2).
public struct CULimits: Equatable, Sendable {
  public var plus: Int
  public var community: Int
  /// When the policy these numbers come from ends; nil for the defaults.
  public var expiresAt: Date?

  public init(plus: Int, community: Int, expiresAt: Date?) {
    self.plus = plus
    self.community = community
    self.expiresAt = expiresAt
  }

  /// Draw Things' `ComputeUnits.threshold(for:)`; Plus verified by the user on the Draw Things app (15 Oct 2026).
  public static let standard = CULimits(plus: 40_000, community: 10_000, expiresAt: nil)
  /// Each boost the user spends on a RUN raises the limit by this much (verified by the user, 15 Oct 2026).
  public static let boostStep = 20_000

  /// The limit the meter shows: Plus (DT Hub assumes it: the meter appears only with DT+ on).
  public var limit: Int { plus }

  public func limit(afterBoosts n: Int) -> Int { limit + max(0, n) * Self.boostStep }

  /// How many boosts a request of `cu` units needs; 0 within the limit.
  public func boostsNeeded(for cu: Int) -> Int {
    guard cu > limit else { return 0 }
    return (cu - limit + Self.boostStep - 1) / Self.boostStep
  }
}

public enum CUState: Equatable, Sendable { case ok, near, over }

/// An estimate set against the limit.
public struct CUReading: Equatable, Sendable {
  /// From this share of the limit the meter warns: the app asked for a boost at 39 972 of 40 000 once.
  public static let nearFraction = 0.9

  public let cu: Int
  public let limit: Int
  public let boosts: Int
  public let state: CUState

  public init(cu: Int, limits: CULimits) {
    self.cu = cu
    limit = limits.limit
    boosts = limits.boostsNeeded(for: cu)
    if cu > limits.limit {
      state = .over
    } else if Double(cu) >= Self.nearFraction * Double(limits.limit) {
      state = .near
    } else {
      state = .ok
    }
  }
}

/// Who knows how to estimate and where the limits come from (DTBridge implements it; the app and HubCore do not
/// know Draw Things).
public protocol ComputeUnitsProviding: Sendable {
  /// nil when the family is not covered or the numbers make no sense.
  func estimate(_ inputs: CUInputs) -> Int?
  /// Always something: the defaults, or the server's active policy.
  func limits() async -> CULimits
}
