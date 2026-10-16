import HubCore
import HubKit
import SwiftUI

/// The tab bar under the header: Generation, then one tab per active plug-in.
struct WorkspaceTabBar: View {
  let workspace: WorkspaceState
  let plugins: PluginRegistry
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      ForEach(workspace.tabs) { tab in
        Button {
          workspace.select(tab.id)
        } label: {
          HStack(spacing: DS.pillIconGap) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 13, weight: .semibold))
            Text(tab.title)
          }
        }
        .buttonStyle(DSTabButtonStyle(isSelected: tab.id == workspace.selectedTabID))
      }
      Spacer(minLength: 0)
    }
  }

  /// The plug-ins on or off, and the way to Preferences: only the icon (and the arrow), always there so a plug-in can be
  /// turned on when none is.
  private var pluginsMenu: some View {
    Menu {
      let loaded = plugins.entries.filter { $0.state == .loaded }
      if loaded.isEmpty {
        Text("header.plugins.none")
      }
      ForEach(loaded) { entry in
        Toggle(
          entry.name,
          isOn: Binding(get: { entry.isActive }, set: { plugins.setActive(entry.id, $0) })
        )
        .disabled(!plugins.isCompatible(entry))
        .help(plugins.isCompatible(entry) ? "" : String(localized: "header.plugins.incompatible"))
      }
      Divider()
      Button("header.plugins.manage") { openSettings() }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "puzzlepiece.extension")
          .font(.system(size: 14, weight: .semibold))
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.secondary)
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .focusEffectDisabled()
    .padding(.horizontal, 10)
    .frame(height: DS.tabHeight)
    .dsGlass(Capsule(style: .continuous))
    .fixedSize()
    .help(String(localized: "header.plugins"))
    .accessibilityLabel(String(localized: "header.plugins"))
  }
}
