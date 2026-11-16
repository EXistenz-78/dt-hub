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
  /// The tab the main window shows; nil when every tab is in a window of its own.
  public private(set) var selectedTabID: WorkspaceTab.ID?
  /// The tabs shown in a window of their own: they stay in the bar, and the main window does not show them. Not
  /// remembered: at the next launch every tab is back in the main window.
  public private(set) var detachedTabIDs: Set<WorkspaceTab.ID> = []

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
  /// dropped. If the selected tab disappears, Generation is selected. A tab that disappears is no longer detached.
  public func setPluginTabs(_ newTabs: [WorkspaceTab]) {
    var seen: Set<WorkspaceTab.ID> = [controlTab.id, generationTab.id]
    pluginTabs = newTabs.filter { seen.insert($0.id).inserted }
    detachedTabIDs.formIntersection(tabs.map(\.id))
    if !attachedTabs.contains(where: { $0.id == selectedTabID }) {
      selectedTabID = replacementTabID
    }
  }

  // MARK: Tabs in a window of their own

  public func isDetached(_ id: WorkspaceTab.ID) -> Bool { detachedTabIDs.contains(id) }

  /// The tab goes to a window of its own; an id that is not in the bar is ignored. If it was the open tab, the main
  /// window shows another one (the tab remembered for the next launch does not change).
  public func detach(_ id: WorkspaceTab.ID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    detachedTabIDs.insert(id)
    if selectedTabID == id { selectedTabID = replacementTabID }
  }

  /// The tab's window closed: the tab is back in the main window, and open there (when it still exists). The tab
  /// remembered for the next launch does not change: the windows also close when the app quits.
  public func attach(_ id: WorkspaceTab.ID) {
    guard detachedTabIDs.remove(id) != nil, tabs.contains(where: { $0.id == id }) else { return }
    selectedTabID = id
  }

  /// The tabs the main window can show.
  private var attachedTabs: [WorkspaceTab] { tabs.filter { !detachedTabIDs.contains($0.id) } }

  /// The tab to open when the open one goes: Generation, then Control, then the first one left.
  private var replacementTabID: WorkspaceTab.ID? {
    let attached = attachedTabs
    return [generationTab.id, controlTab.id].first { id in attached.contains { $0.id == id } } ?? attached.first?.id
  }

  /// Selects a tab (and remembers it); an id that is not in the bar, or of a tab in a window of its own, is ignored.
  public func select(_ id: WorkspaceTab.ID) {
    guard attachedTabs.contains(where: { $0.id == id }) else { return }
    selectedTabID = id
    defaults.set(id, forKey: Self.selectedTabKey)
  }

  /// The tab to the right of the selected one (⌃Page Down); the last one stays. Tabs in a window of their own are
  /// skipped.
  public func selectNext() { select(offset: 1) }

  /// The tab to the left of the selected one (⌃Page Up); the first one stays.
  public func selectPrevious() { select(offset: -1) }

  private func select(offset: Int) {
    let attached = attachedTabs
    guard let index = attached.firstIndex(where: { $0.id == selectedTabID }) else { return }
    let target = min(max(index + offset, 0), attached.count - 1)
    select(attached[target].id)
  }
}
