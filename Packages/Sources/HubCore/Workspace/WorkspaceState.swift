import Observation

/// The tab bar under the header: the built-in Generation tab first, then one tab
/// per active plug-in, in activation order (spec §7).
@MainActor
@Observable
public final class WorkspaceState {
  public let generationTab: WorkspaceTab
  public private(set) var pluginTabs: [WorkspaceTab] = []
  public private(set) var selectedTabID: WorkspaceTab.ID

  public init(generationTab: WorkspaceTab) {
    self.generationTab = generationTab
    self.selectedTabID = generationTab.id
  }

  public var tabs: [WorkspaceTab] { [generationTab] + pluginTabs }

  /// Replaces the plug-in tabs. A tab reusing the Generation id, or an id already
  /// listed, is dropped. If the selected tab disappears, Generation is selected.
  public func setPluginTabs(_ newTabs: [WorkspaceTab]) {
    var seen: Set<WorkspaceTab.ID> = [generationTab.id]
    pluginTabs = newTabs.filter { seen.insert($0.id).inserted }
    if !tabs.contains(where: { $0.id == selectedTabID }) {
      selectedTabID = generationTab.id
    }
  }

  /// Selects a tab; an id that is not in the bar is ignored.
  public func select(_ id: WorkspaceTab.ID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    selectedTabID = id
  }
}
