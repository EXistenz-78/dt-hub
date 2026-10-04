import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// Preferences › Plug-ins: what is installed, the switches, add (a file chosen or dropped) and remove.
struct PluginsPreferencesView: View {
  let plugins: PluginRegistry
  @State private var offer: PluginInstallOffer?
  @State private var problem: String?
  @State private var isTargeted = false

  var body: some View {
    Form {
      Section {
        if plugins.entries.isEmpty {
          Text("prefs.plugins.empty").foregroundStyle(.secondary)
        }
        ForEach(plugins.entries) { entry in
          row(entry)
        }
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if let problem { Text(verbatim: problem).foregroundStyle(DS.remove) }
          if plugins.needsRestart {
            HStack(spacing: DS.controlGap) {
              Text("prefs.plugins.restart.note").foregroundStyle(.secondary)
              Spacer(minLength: 0)
              Button("prefs.plugins.restart") { AppRelaunch.relaunch() }
                .buttonStyle(DSPillButtonStyle(prominent: true))
            }
          }
          Text("prefs.plugins.note").foregroundStyle(.secondary)
          if let page = PluginText.downloadPage {
            Link("prefs.plugins.download", destination: page)
          }
        }
      }
      Section {
        HStack(spacing: DS.controlGap) {
          Spacer(minLength: 0)
          Button("prefs.plugins.add") { choose() }
            .buttonStyle(DSPillButtonStyle(prominent: true))
        }
      }
    }
    .formStyle(.grouped)
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0).padding(4))
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: { $0.pathExtension == "dthubplugin" }) else { return false }
      propose(url)
      return true
    } isTargeted: { isTargeted = $0 }
    .confirmationDialog(
      offer.map { String(format: String(localized: "prefs.plugins.confirm.title"), $0.info.name) } ?? "",
      isPresented: Binding(get: { offer != nil }, set: { if !$0 { offer = nil } }), presenting: offer
    ) { offer in
      Button("prefs.plugins.confirm.add") { install(offer) }
      Button("prefs.plugins.confirm.cancel", role: .cancel) {}
    } message: { offer in
      Text(
        String(format: String(localized: "prefs.plugins.confirm.message"), offer.info.version)
          + (offer.replacing.map { "\n" + String(format: String(localized: "prefs.plugins.confirm.replacing"), $0) } ?? ""))
    }
  }

  private func row(_ entry: PluginEntry) -> some View {
    HStack(spacing: DS.controlGap) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: "\(entry.name) \(entry.version)")
        Text(verbatim: PluginText.state(entry)).font(.caption)
          .foregroundStyle({ if case .failed = entry.state { DS.remove } else { Color.secondary } }())
        if let notice = plugins.lastNotice(of: entry.id) {
          Text(verbatim: String(format: String(localized: "prefs.plugins.lastNotice"), notice.text)).font(.caption)
            .foregroundStyle(notice.isError ? DS.remove : Color.secondary).lineLimit(2)
        }
      }
      Spacer(minLength: 0)
      if case .failed = entry.state {
      } else {
        Toggle(isOn: Binding(get: { plugins.isEnabled(entry.id) }, set: { plugins.setEnabled(entry.id, $0) })) {
          Text(verbatim: entry.name)
        }
        .labelsHidden()
        .toggleStyle(.switch)
      }
      Button("prefs.plugins.remove", role: .destructive) { remove(entry) }
        .buttonStyle(DSPillButtonStyle())
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true  // a .dthubplugin is a package, a folder on disk (older macOS records may still treat it as one)
    panel.allowsMultipleSelection = false
    panel.message = String(localized: "prefs.plugins.choose")
    if panel.runModal() == .OK, let url = panel.url { propose(url) }
  }

  private func propose(_ url: URL) {
    problem = nil
    do {
      offer = try plugins.offer(for: url)
    } catch {
      problem = PluginText.error(error)
    }
  }

  private func install(_ offer: PluginInstallOffer) {
    do {
      try plugins.install(offer)
      problem = nil
    } catch {
      problem = PluginText.error(error)
    }
  }

  private func remove(_ entry: PluginEntry) {
    do {
      try plugins.remove(entry.id)
      problem = nil
    } catch {
      problem = PluginText.error(error)
    }
  }
}
