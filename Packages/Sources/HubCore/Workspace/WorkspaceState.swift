import Foundation
import Observation

/// The tab bar under the header: one tab per active plug-in, in activation order, then the built-in
/// Control and Generation tabs (spec §7, tab Control spec §3; plug-ins first since 4 October 2026).
@MainActor
@Observable
public final class WorkspaceState {
  public static let selectedTabKey = "workspace.selectedTab"

  public let controlTab: WorkspaceTab
  public let generationTab: WorkspaceTab
  public private(set) var pluginTabs: [WorkspaceTab] = []
  public private(set) var selectedTabID: WorkspaceTab.ID

  @ObservationIgnored private let defaults: UserDefaults

  /// Opens the tab used last, when it still exists; otherwise Generation.
  public init(controlTab: WorkspaceTab, generationTab: WorkspaceTab, defaults: UserDefaults = .standard) {
    self.controlTab = controlTab
    self.generationTab = generationTab
    self.defaults = defaults
    let saved = defaults.string(forKey: Self.selectedTabKey)
    selectedTabID = saved == controlTab.id ? controlTab.id : generationTab.id
  }

  public var tabs: [WorkspaceTab] { pluginTabs + [controlTab, generationTab] }

  /// Replaces the plug-in tabs. A tab reusing a built-in id, or an id already listed, is
  /// dropped. If the selected tab disappears, Generation is selected.
  public func setPluginTabs(_ newTabs: [WorkspaceTab]) {
    var seen: Set<WorkspaceTab.ID> = [controlTab.id, generationTab.id]
    pluginTabs = newTabs.filter { seen.insert($0.id).inserted }
    if !tabs.contains(where: { $0.id == selectedTabID }) {
      selectedTabID = generationTab.id
    }
  }

  /// Selects a tab (and remembers it); an id that is not in the bar is ignored.
  public func select(_ id: WorkspaceTab.ID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    selectedTabID = id
    defaults.set(id, forKey: Self.selectedTabKey)
  }
}
