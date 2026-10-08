import AppKit
import HubCore
import HubKit
import SwiftUI

/// Preferences › Output: where generated images are saved (spec §7).
struct OutputPreferencesView: View {
  let controller: GenerationController
  let projects: ProjectManager

  var body: some View {
    Form {
      Section {
        LabeledContent(String(localized: "prefs.output.folder")) {
          Text(verbatim: controller.outputFolder.path)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      } footer: {
        Text("prefs.output.note").foregroundStyle(.secondary)
      }
      Section {
        HStack(spacing: DS.controlGap) {
          Spacer(minLength: 0)
          Button("prefs.output.reveal") { reveal() }
            .buttonStyle(DSPillButtonStyle())
          Button("prefs.output.choose") { choose() }
            .buttonStyle(DSPillButtonStyle(prominent: true))
        }
      }
    }
    .formStyle(.grouped)
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = controller.outputFolder
    if panel.runModal() == .OK, let url = panel.url {
      controller.setOutputFolder(url)
      // The projects are the subfolders of this folder: read them again (the open one may not be here).
      projects.refresh()
    }
  }

  private func reveal() {
    try? FileManager.default.createDirectory(at: controller.outputFolder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(controller.outputFolder)
  }
}
