import HubCore
import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7).
struct PreferencesView: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let languageModel: LanguageModelManager
  let download: LanguageModelDownloadController
  let plugins: PluginRegistry

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        DrawThingsPreferencesView(connection: connection)
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        LanguagePreferencesView(manager: languageModel, download: download, connection: connection)
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        OutputPreferencesView(controller: generation)
      }
      Tab("prefs.tab.plugins", systemImage: "puzzlepiece.extension") {
        PluginsPreferencesView(plugins: plugins)
      }
    }
    .frame(width: 560, height: 420)
  }
}
