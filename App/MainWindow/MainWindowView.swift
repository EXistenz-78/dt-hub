import AppKit
import HubCore
import HubKit
import SwiftUI

/// Header, tab bar, and the content of the selected tab (spec §7).
struct MainWindowView: View {
  let workspace: WorkspaceState
  let connection: DrawThingsConnection
  let generation: GenerationController
  let plugins: PluginRegistry

  /// What the plug-ins are told about: the model and its family.
  private var contextKey: [String?] {
    let model = connection.selection.selectedModel(in: connection.monitor.catalog)
    return [model?.file, model?.family]
  }

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      HeaderBar(connection: connection, generation: generation, plugins: plugins)
      ManagedServerBanner(connection: connection)
      DSTabFrame {
        WorkspaceTabBar(workspace: workspace)
      } content: {
        tabContent
      }
    }
    .padding(20)
    .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 820)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
    .overlay(alignment: .bottom) { PluginNoticeBanner(plugins: plugins) }
    .environment(plugins)
    .environment(plugins.contributions)
    .sheet(
      isPresented: Binding(
        get: { !plugins.contributions.conflicts.isEmpty }, set: { if !$0 { plugins.contributions.dismissConflicts() } })
    ) {
      ContributionConflictSheet(plugins: plugins)
    }
    .task(id: contextKey) {
      plugins.updateContext(model: contextKey[0], family: contextKey[1], parameters: generation.parameters)
      workspace.setPluginTabs(plugins.activeTabs)
    }
    .onChange(of: plugins.activeTabs) { workspace.setPluginTabs(plugins.activeTabs) }
  }

  @ViewBuilder private var tabContent: some View {
    if workspace.selectedTabID == WorkspaceTab.controlID {
      ControlTabView(generation: generation, connection: connection)
    } else if workspace.selectedTabID == WorkspaceTab.generationID {
      GenerationTabView(controller: generation, connection: connection)
    } else if let controller = plugins.viewController(forTab: workspace.selectedTabID) as? NSViewController {
      // One view per tab: without the id SwiftUI keeps the first plug-in's controller when another plug-in tab is chosen.
      PluginTabView(controller: controller).id(workspace.selectedTabID)
    } else {
      EmptyView()
    }
  }
}
