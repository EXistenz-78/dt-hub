import AppKit
import HubCore
import HubKit
import SwiftUI

/// Preferences › LLM: where the prompts for Enhance/Generate Prompt are (Data/DTHub), which family has a file of its
/// own in `custom/`, and what the language model receives for a family and a task (read-only preview).
struct PromptLibrarySection: View {
  private let library = PromptLibrary.live

  @State private var familyID = "qwen_image_2.1"
  @State private var task = PromptTask.enhance
  @State private var families: [FamilyPrompt] = []
  @State private var preview = ""
  @State private var problems: [String] = []

  var body: some View {
    Section {
      Button("prefs.prompts.open") { NSWorkspace.shared.open(library.folderURL) }
      Picker("prefs.prompts.family", selection: $familyID) {
        ForEach(families, id: \.id) { family in
          Text(verbatim: family.isCustomized ? "\(family.label) · " + String(localized: "prefs.prompts.custom") : family.label)
            .tag(family.id)
        }
      }
      Picker("prefs.prompts.task", selection: $task) {
        Text("prefs.prompts.task.enhance").tag(PromptTask.enhance)
        Text("prefs.prompts.task.describe").tag(PromptTask.describe)
      }
      .pickerStyle(.segmented)
      DisclosureGroup("prefs.prompts.preview") {
        Text(verbatim: preview)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      ForEach(problems, id: \.self) { problem in
        Text(verbatim: problem)
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    } header: {
      Text("prefs.prompts.title")
    } footer: {
      Text("prefs.prompts.note")
        .foregroundStyle(.secondary)
    }
    .onAppear(perform: refresh)
    .onChange(of: familyID) { refresh() }
    .onChange(of: task) { refresh() }
  }

  private func refresh() {
    families = library.families()
    preview = library.system(task: task, family: familyID)
    problems = library.problems()
  }
}
