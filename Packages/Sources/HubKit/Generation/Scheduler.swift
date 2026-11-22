/// ComfyUI's schedulers, which space the steps independently of the sampler. The raw values are the numbers the
/// configuration's `scheduler` field carries to the server (the Atelier fork of the Draw Things engine); 0 leaves
/// the schedule the sampler has always used. A server without the field ignores it.
public enum Scheduler: Int, CaseIterable, Identifiable, Codable, Sendable {
  case samplerDefault = 0
  case simple = 1
  case sgmUniform = 2
  case normal = 3
  case karras = 4
  case exponential = 5
  case linearQuadratic = 6
  case beta = 7

  public var id: Int { rawValue }

  /// The ComfyUI names, the same in every language. `samplerDefault` has no name of its own: the card says "Own".
  public var displayName: String? {
    switch self {
    case .samplerDefault: nil
    case .simple: "Simple"
    case .sgmUniform: "SGM Uniform"
    case .normal: "Normal"
    case .karras: "Karras"
    case .exponential: "Exponential"
    case .linearQuadratic: "Linear Quadratic"
    case .beta: "Beta"
    }
  }

  /// The Substep samplers keep their own schedule: the server ignores a scheduler for them.
  public static func isUsed(by sampler: Sampler) -> Bool {
    sampler != .eulerASubstep && sampler != .dpmppSDESubstep
  }
}
