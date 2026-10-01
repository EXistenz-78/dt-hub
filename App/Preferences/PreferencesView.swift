import HubCore
import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7).
struct PreferencesView: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let languageModel: LanguageModelManager

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        DrawThingsPreferencesView(connection: connection)
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        LanguagePreferencesView(manager: languageModel, connection: connection)
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        OutputPreferencesView(controller: generation)
      }
    }
    .frame(width: 560, height: 420)
  }
}
