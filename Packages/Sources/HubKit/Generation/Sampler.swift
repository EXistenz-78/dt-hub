/// The Draw Things samplers, with the raw values of its configuration schema.
public enum Sampler: Int, CaseIterable, Identifiable, Codable, Sendable {
  case dpmpp2mKarras = 0
  case eulerAncestral = 1
  case ddim = 2
  case plms = 3
  case dpmppSDEKarras = 4
  case uniPC = 5
  case lcm = 6
  case eulerASubstep = 7
  case dpmppSDESubstep = 8
  case tcd = 9
  case eulerATrailing = 10
  case dpmppSDETrailing = 11
  case dpmpp2mAYS = 12
  case eulerAAYS = 13
  case dpmppSDEAYS = 14
  case dpmpp2mTrailing = 15
  case ddimTrailing = 16
  case uniPCTrailing = 17
  case uniPCAYS = 18
  case tcdTrailing = 19

  public var id: Int { rawValue }

  /// The name Draw Things shows. Technical names, the same in every language.
  public var displayName: String {
    switch self {
    case .dpmpp2mKarras: "DPM++ 2M Karras"
    case .eulerAncestral: "Euler Ancestral"
    case .ddim: "DDIM"
    case .plms: "PLMS"
    case .dpmppSDEKarras: "DPM++ SDE Karras"
    case .uniPC: "UniPC"
    case .lcm: "LCM"
    case .eulerASubstep: "Euler A Substep"
    case .dpmppSDESubstep: "DPM++ SDE Substep"
    case .tcd: "TCD"
    case .eulerATrailing: "Euler A Trailing"
    case .dpmppSDETrailing: "DPM++ SDE Trailing"
    case .dpmpp2mAYS: "DPM++ 2M AYS"
    case .eulerAAYS: "Euler A AYS"
    case .dpmppSDEAYS: "DPM++ SDE AYS"
    case .dpmpp2mTrailing: "DPM++ 2M Trailing"
    case .ddimTrailing: "DDIM Trailing"
    case .uniPCTrailing: "UniPC Trailing"
    case .uniPCAYS: "UniPC AYS"
    case .tcdTrailing: "TCD Trailing"
    }
  }
}
