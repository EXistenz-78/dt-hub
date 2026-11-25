/// How a pass of a plug-in's pipeline tiles the picture so that its edges meet (the custom server's `seamlessTile`
/// field). It is never a setting of the Generation tab: it belongs to the steps a plug-in proposes.
public enum SeamlessTile: String, Codable, Sendable, CaseIterable {
  case both
  case leftRight
  case upDown

  /// The byte the configuration carries: 1 left-right, 2 up-down, 3 both (0, off, is never sent).
  public var configurationValue: Int8 {
    switch self {
    case .leftRight: 1
    case .upDown: 2
    case .both: 3
    }
  }

  /// The families (DT Hub's keys) whose versions on the custom server read the field.
  public static let families: Set<String> = ["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"]

  /// Why a seamless step cannot run now; nil when it can.
  public static func problem(customServer: Bool, family: String?) -> String? {
    guard customServer else { return "seamless: the custom server is not running." }
    guard let family, families.contains(family) else { return "seamless: this model family does not support it." }
    return nil
  }
}
