import HubCore
import HubKit
import SwiftUI

/// The tab bar under the header: one tab per active plug-in, then Control and Generation. Each tab shows only its icon;
/// the open one and the one under the mouse show their name too, and the others move aside to make room.
struct WorkspaceTabBar: View {
  let workspace: WorkspaceState
  let plugins: PluginRegistry
  /// True when the Moodboard has images or there is a start image: Control, when closed, shows a small teal dot.
  var controlHasImages = false
  @Environment(\.openSettings) private var openSettings
  /// The tab the mouse rests on: its name shows too (one at a time).
  @State private var hoveredTabID: String?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      ForEach(workspace.tabs) { tab in
        WorkspaceTabButton(
          tab: tab, isSelected: tab.id == workspace.selectedTabID, hoveredID: $hoveredTabID,
          showsBadge: tab.id == WorkspaceTab.controlID && controlHasImages
        ) {
          workspace.select(tab.id)
        }
      }
      Spacer(minLength: 0)
    }
    // The name of the tab under the mouse stays open while the mouse is on the bar: leaving a tab for the next one
    // closes one name and opens the other in one step, so the tabs do not move under the pointer in between.
    .onHover { inside in
      if !inside, hoveredTabID != nil { withAnimation(.easeOut(duration: 0.15)) { hoveredTabID = nil } }
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

/// One tab: its icon, and its name when it is the open tab or the mouse rests on it. The first name appears after a
/// short rest (120 ms); once one is open, moving to another tab swaps the names at once and the open name stays until
/// the mouse leaves the bar, so the tabs do not slide away from the pointer.
private struct WorkspaceTabButton: View {
  let tab: WorkspaceTab
  let isSelected: Bool
  @Binding var hoveredID: String?
  /// A small teal dot on the icon; only while the tab is not the open one.
  var showsBadge = false
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
          .overlay(alignment: .topTrailing) {
            if showsBadge && !isSelected {
              Circle().fill(DS.accent).frame(width: 7, height: 7)
                .offset(x: 4, y: -3)
                .accessibilityHidden(true)
            }
          }
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
      // Leaving a tab changes nothing: the bar clears the name when the mouse leaves it altogether.
      guard inside else { return }
      if hoveredID != nil {
        // Coming from another tab: swap at once, so the tabs on the right do not slide away from the pointer.
        withAnimation(animation) { hoveredID = tab.id }
      } else {
        pendingHover = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(120))
          guard !Task.isCancelled else { return }
          withAnimation(animation) { hoveredID = tab.id }
        }
      }
    }
  }
}
