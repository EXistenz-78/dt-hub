import SwiftUI

/// 40pt capsule, icon 14 semibold + text 13 semibold. `prominent` fills it teal:
/// the one call to action on the screen. Disabled buttons fade to 40%.
public struct DSPillButtonStyle: ButtonStyle {
  let prominent: Bool

  public init(prominent: Bool = false) { self.prominent = prominent }

  public func makeBody(configuration: Configuration) -> some View {
    PillBody(configuration: configuration, prominent: prominent)
  }

  private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      let label = configuration.label
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, DS.pillHPadding)
        .frame(height: DS.pillHeight)

      Group {
        if prominent {
          label
            .foregroundStyle(Color.black.opacity(0.88))
            .background(DS.accent, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: DS.accent.opacity(isEnabled ? 0.35 : 0), radius: 9, x: 0, y: 3)
        } else {
          label
            .foregroundStyle(.primary)
            .dsGlass(Capsule(style: .continuous))
        }
      }
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}

/// 40×40 glass circle, icon 16 semibold, for actions an icon can carry alone.
public struct DSGlassCircleButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(.primary)
      .frame(width: DS.glassButtonSize, height: DS.glassButtonSize)
      .dsGlass(Circle())
      .opacity(configuration.isPressed ? 0.75 : 1)
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// A tab of the workspace tab bar: 32pt capsule, teal glass when selected.
public struct DSTabButtonStyle: ButtonStyle {
  let isSelected: Bool

  public init(isSelected: Bool) { self.isSelected = isSelected }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary))
      .padding(.horizontal, DS.pillHPadding)
      .frame(height: DS.tabHeight)
      .background {
        if isSelected {
          Capsule(style: .continuous).fill(Color.clear)
            .dsGlass(Capsule(style: .continuous), tint: DS.accent.opacity(0.7))
        }
      }
      .contentShape(Capsule(style: .continuous))
      .opacity(configuration.isPressed ? 0.75 : 1)
  }
}

/// The stock `.checkbox` style is nearly invisible on dark glass: the box is drawn
/// explicitly and fills teal when on.
public struct DSCheckboxToggleStyle: ToggleStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: DS.controlGap) {
        ZStack {
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(configuration.isOn ? DS.accent : Color.white.opacity(0.10))
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(configuration.isOn ? Color.clear : Color.white.opacity(0.30), lineWidth: 1)
          if configuration.isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Color.black.opacity(0.88))
          }
        }
        .frame(width: 18, height: 18)

        configuration.label
          .font(.subheadline)
          .foregroundStyle(.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// The label of a header menu: icon, title, an optional secondary detail (e.g. the model
/// family), and a small chevron. The chevron is drawn here because a plain-styled `Menu`
/// hides the system indicator.
public struct DSMenuLabel: View {
  let title: String
  let detail: String?
  let systemImage: String

  public init(_ title: String, detail: String? = nil, systemImage: String) {
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
  }

  public var body: some View {
    HStack(spacing: DS.pillIconGap) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .accessibilityHidden(true)
      Text(title)
        .lineLimit(1)
      if let detail {
        Text(detail)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Image(systemName: "chevron.down")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}

extension View {
  /// A `Menu` drawn as a glass pill. On macOS a Menu is an AppKit pop-up that ignores
  /// custom ButtonStyles, so the glass goes around a plain-styled menu instead.
  /// Use `DSMenuLabel` as the menu's label.
  public func dsMenuPill() -> some View {
    self
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .focusEffectDisabled()
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, DS.pillHPadding)
      .frame(height: DS.pillHeight)
      .dsGlass(Capsule(style: .continuous))
      .fixedSize()
  }
}
