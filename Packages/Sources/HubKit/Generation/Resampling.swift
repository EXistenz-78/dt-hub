import Foundation

/// How the start image is brought to the canvas's scale (`2026-11-28-ingrandimento-immagine-partenza-design.md`).
/// In the parameters `nil` means automatic: the user's saved choice for the model's family, else the factory one.
public enum Resampling: String, Codable, Sendable, CaseIterable {
  /// Core Graphics at high quality: what DT Hub always did, the sharpest.
  case coreGraphics
  /// Bicubic B=0 C=0.5 (the bicubic of PIL, the one SeedVR2's own pipelines use).
  case catmullRom
  /// Bicubic B=C=1/3.
  case mitchell
  /// Bicubic B=1 C=0, the softest.
  case bSpline
  case bilinear
  case lanczos
  case nearest

  /// SeedVR2 turns the sharp scaling's small artifacts into texture (measured on SeedVR2 7B): it gets Catmull-Rom.
  static let factoryByFamily: [String: Resampling] = ["seedvr2_3b": .catmullRom, "seedvr2_7b": .catmullRom]

  /// The algorithm a family gets when the user saved none: Core Graphics for every family but SeedVR2.
  public static func factory(forFamily family: String?) -> Resampling {
    family.flatMap { factoryByFamily[$0] } ?? .coreGraphics
  }

  /// The algorithm a RUN uses: the one chosen in the parameters, else the one the user saved for the family, else
  /// the factory one.
  public static func effective(explicit: Resampling?, family: String?, saved: [String: Resampling]) -> Resampling {
    explicit ?? family.flatMap { saved[$0] } ?? factory(forFamily: family)
  }
}
