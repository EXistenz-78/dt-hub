import HubKit

/// The names of the start image algorithms, as the Canvas card and its messages show them.
enum ResamplingText {
  static func name(_ method: Resampling) -> String {
    switch method {
    case .coreGraphics: String(localized: "control.resampling.coreGraphics")
    case .catmullRom: String(localized: "control.resampling.catmullRom")
    case .mitchell: String(localized: "control.resampling.mitchell")
    case .bSpline: String(localized: "control.resampling.bSpline")
    case .bilinear: String(localized: "control.resampling.bilinear")
    case .lanczos: String(localized: "control.resampling.lanczos")
    case .nearest: String(localized: "control.resampling.nearest")
    }
  }
}
