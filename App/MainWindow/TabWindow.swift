import AppKit
import HubCore
import HubKit
import SwiftUI

/// A tab in a window of its own (opened from the tab bar: the tab's menu, or a click with Option). While the window is
/// open the tab stays in the bar, in orange, and the main window does not show it; closing the window brings it back.
enum TabWindow {
  static let id = "tab"
  /// The tabs are made for the main window: a tab's own window gives them at least the room they have there.
  static let minSize = CGSize(width: 880, height: 540)
  static let defaultSize = CGSize(width: 1000, height: 760)
}

/// What a tab shows: the main window uses it for the open tab, a tab's own window for its tab.
struct WorkspaceTabContent: View {
  let tabID: WorkspaceTab.ID
  let workspace: WorkspaceState
  let generation: GenerationController
  let connection: DrawThingsConnection
  let plugins: PluginRegistry
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    if tabID == WorkspaceTab.controlID {
      ControlTabView(generation: generation, connection: connection)
    } else if tabID == WorkspaceTab.generationID {
      GenerationTabView(controller: generation, connection: connection, openControl: { show(WorkspaceTab.controlID) })
    } else if let controller = plugins.viewController(forTab: tabID) as? NSViewController {
      // One view per tab: without the id SwiftUI keeps the first plug-in's controller when another plug-in tab is chosen.
      PluginTabView(controller: controller).id(tabID)
    } else {
      EmptyView()
    }
  }

  /// Shows another tab: its window comes to the front when it has one, otherwise the main window opens it.
  private func show(_ id: WorkspaceTab.ID) {
    if workspace.isDetached(id) {
      openWindow(id: TabWindow.id, value: id)
    } else {
      workspace.select(id)
    }
  }
}

/// The content of a tab's own window: the tab alone, without the header, the queue or the banners.
struct TabWindowView: View {
  let tabID: WorkspaceTab.ID
  let workspace: WorkspaceState
  let generation: GenerationController
  let connection: DrawThingsConnection
  let plugins: PluginRegistry
  @Environment(\.dismissWindow) private var dismissWindow

  private var title: String { workspace.tabs.first { $0.id == tabID }?.title ?? "" }

  var body: some View {
    // As in the main window, the tab is laid out once, in the space it is given.
    Color.clear
      .overlay {
        // Only while the tab is this window's: a plug-in has one view controller, and it cannot be in two windows.
        if workspace.isDetached(tabID) {
          WorkspaceTabContent(
            tabID: tabID, workspace: workspace, generation: generation, connection: connection, plugins: plugins)
        }
      }
      .padding(20)
      .frame(
        minWidth: TabWindow.minSize.width, idealWidth: TabWindow.defaultSize.width,
        minHeight: TabWindow.minSize.height, idealHeight: TabWindow.defaultSize.height
      )
      .background(DSBackground())
      .background(DSWindowConfigurator())
      .background(NoWindowTabbing())
      .background(WindowFrameKeeper(key: "tabWindow.frame.\(tabID)", minSize: TabWindow.minSize))
      .tint(DS.accent)
      .environment(plugins)
      .environment(plugins.contributions)
      .navigationTitle(title)
      .onAppear {
        // The tab bar detaches the tab before it opens the window; this covers a window opened in any other way.
        workspace.detach(tabID)
        if workspace.isDetached(tabID) {
          // What changed meanwhile without the model changing: the plug-in hears about it when its tab is shown.
          plugins.refreshContext()
        } else {
          dismissWindow(id: TabWindow.id, value: tabID)
        }
      }
      .onDisappear { workspace.attach(tabID) }
      // The plug-in was turned off, or does not work with the model chosen now: its tab is gone, and so is the window.
      .onChange(of: workspace.isDetached(tabID)) { _, isDetached in
        if !isDetached { dismissWindow(id: TabWindow.id, value: tabID) }
      }
  }
}

/// Keeps a tab's window out of the system's window tabs ("Prefer tabs: always", or a window in full screen): as a
/// system tab behind another one the window is taken off the screen, and the app would read that as closed.
private struct NoWindowTabbing: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { Marker() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class Marker: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.tabbingMode = .disallowed
    }
  }
}
