import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// The bar at the top of the Generation tab (decided with the user, 1 October 2026): the
/// Preset menu and the JSON editor button.
struct PresetBar: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection
  @State private var saving = false
  @State private var managing = false
  @State private var editingJSON = false
  @State private var importMessage: String?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      Menu {
        if controller.presets.names.isEmpty {
          Text("preset.none")
        }
        ForEach(controller.presets.names, id: \.self) { name in
          Button {
            if let error = controller.loadPreset(named: name, with: connection) {
              importMessage = Self.text(of: error)
            } else {
              importMessage = nil
            }
          } label: {
            Text(verbatim: name)
          }
        }
        Divider()
        Button {
          saving = true
        } label: {
          Text("preset.saveAs")
        }
        Button {
          managing = true
        } label: {
          Text("preset.manage")
        }
        .disabled(controller.presets.names.isEmpty)
        Button {
          importFile()
        } label: {
          Text("preset.import")
        }
      } label: {
        DSMenuLabel(String(localized: "preset.menu"), systemImage: "slider.horizontal.below.rectangle")
      }
      .dsMenuPill()

      Button {
        editingJSON = true
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "curlybraces")
            .accessibilityHidden(true)
          Text("json.button")
          if !controller.parameters.extra.isEmpty {
            Text(verbatim: "· \(controller.parameters.extra.count)")
              .foregroundStyle(DS.accent)
              .monospacedDigit()
          }
        }
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "json.button.help"))

      if let importMessage {
        Text(importMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    // The list is the folder's: files added or changed by hand show up when the window comes back.
    .onAppear { controller.presets.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      controller.presets.refresh()
    }
    .sheet(isPresented: $saving) {
      SavePresetSheet(controller: controller, connection: connection)
    }
    .sheet(isPresented: $managing) {
      ManagePresetsSheet(controller: controller)
    }
    .sheet(isPresented: $editingJSON) {
      JSONEditorSheet(controller: controller, connection: connection)
    }
  }

  /// What went wrong loading a preset.
  static func text(of error: PresetError) -> String {
    switch error {
    case .unreadable(let name): String(format: String(localized: "preset.load.unreadable"), name)
    case .notFound(let name): String(format: String(localized: "pipeline.missingPreset"), name)
    case .invalidName: String(localized: "preset.save.invalidName")
    case .nameTaken: String(localized: "preset.rename.taken")
    case .cannotWrite(let reason): reason
    }
  }

  /// Asks for a file with a list of presets; the result is told in the bar.
  private func importFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.message = String(localized: "preset.import.message")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let result = controller.importPresets(from: url)
    importMessage = String(
      format: String(localized: "preset.import.result"), result.presets.count, result.skipped)
  }
}
