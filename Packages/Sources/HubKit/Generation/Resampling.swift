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

  /// The name the Results window shows (technical names, like the samplers').
  public var displayName: String {
    switch self {
    case .coreGraphics: "Core Graphics"
    case .catmullRom: "Catmull-Rom"
    case .mitchell: "Mitchell"
    case .bSpline: "B-spline"
    case .bilinear: "Bilinear"
    case .lanczos: "Lanczos"
    case .nearest: "Nearest"
    }
  }

  /// The names the MCP tools use: "automatic" (nil) and the raw values, in the menu's order.
  public static let agentNames = ["automatic"] + allCases.map(\.rawValue)

  /// The name an agent sees for a choice.
  public static func agentValue(_ value: Resampling?) -> String { value?.rawValue ?? "automatic" }

  /// The choice an agent's name stands for: `.some(nil)` for automatic, nil for a name that is not one of `agentNames`.
  public static func choice(agentValue: String) -> Resampling?? {
    if agentValue == "automatic" { return .some(nil) }
    return Resampling(rawValue: agentValue).map { .some($0) }
  }
}
