import SwiftUI

/// Visual tokens of the FlatPlanner design system, shared by DT Hub and its plug-ins (spec §7).
/// Ported from Sphere Light Reference's DesignSystem.swift, which lifted them from FlatPlanner.
public enum DS {
  /// The single brand accent, #3EC8C8. Stated literally: the system teal is lighter and bluer.
  public static let accent = Color(red: 62.0 / 255, green: 200.0 / 255, blue: 200.0 / 255)
  /// Accent mixed 25% with black, #2C9797: filled blocks that carry text.
  public static let accentDeep = Color(red: 44.0 / 255, green: 151.0 / 255, blue: 151.0 / 255)
  /// #F09837: whatever removes or excludes — destructive actions, the negative prompt.
  public static let remove = Color(red: 240.0 / 255, green: 152.0 / 255, blue: 55.0 / 255)

  // Concentric radii: the stroke sits 1pt inside the fill so it nests into the curve.
  public static let panelRadius: CGFloat = 19
  public static let panelStrokeRadius: CGFloat = 18
  public static let boxRadius: CGFloat = 10
  public static let minorRadius: CGFloat = 12

  // Spacing rhythm.
  public static let groupGap: CGFloat = 18
  public static let panelPadding: CGFloat = 14
  public static let boxPadding: CGFloat = 12
  public static let rowGap: CGFloat = 10
  public static let controlGap: CGFloat = 8

  public static let glassButtonSize: CGFloat = 40
  public static let pillHeight: CGFloat = 40
  public static let pillHPadding: CGFloat = 14
  public static let pillIconGap: CGFloat = 7
  public static let tabHeight: CGFloat = 32
}
