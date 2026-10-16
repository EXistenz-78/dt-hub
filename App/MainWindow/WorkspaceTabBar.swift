import HubCore
import HubKit
import SwiftUI

/// The tab bar under the header: one tab per active plug-in, then Control and Generation. Each tab shows only its icon;
/// the open one and the one under the mouse show their name too, and the others move aside to make room.
struct WorkspaceTabBar: View {
  let workspace: WorkspaceState
  let plugins: PluginRegistry
  @Environment(\.openSettings) private var openSettings
  /// The tab the mouse rests on: its name shows too (one at a time).
  @State private var hoveredTabID: String?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      ForEach(workspace.tabs) { tab in
        WorkspaceTabButton(
          tab: tab, isSelected: tab.id == workspace.selectedTabID, hoveredID: $hoveredTabID
        ) {
          workspace.select(tab.id)
        }
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

/// One tab: its icon, and its name when it is the open tab or the mouse rests on it. The name appears after a short
/// rest (120 ms) so that crossing the bar quickly does not open and close every tab in the way, which would move the
/// tabs under the pointer.
private struct WorkspaceTabButton: View {
  let tab: WorkspaceTab
  let isSelected: Bool
  @Binding var hoveredID: String?
  let select: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pendingHover: Task<Void, Never>?

  private var isExpanded: Bool { isSelected || hoveredID == tab.id }
  private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

  var body: some View {
    Button(action: select) {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: tab.systemImage)
          .font(.system(size: 13, weight: .semibold))
        if isExpanded {
          Text(tab.title)
            .lineLimit(1)
            .transition(.opacity)
        }
      }
    }
    .buttonStyle(DSTabButtonStyle(isSelected: isSelected))
    .animation(animation, value: isExpanded)
    // The name is always the VoiceOver label and the tooltip, shown or not.
    .accessibilityLabel(tab.title)
    .help(tab.title)
    .onHover { inside in
      pendingHover?.cancel()
      pendingHover = nil
      if inside {
        pendingHover = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(120))
          guard !Task.isCancelled else { return }
          withAnimation(animation) { hoveredID = tab.id }
        }
      } else if hoveredID == tab.id {
        withAnimation(animation) { hoveredID = nil }
      }
    }
  }
}
