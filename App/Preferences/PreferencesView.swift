import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7). Empty in M1.
struct PreferencesView: View {
  let connection: DrawThingsConnection

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        PreferencesPlaceholder()
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        PreferencesPlaceholder()
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        PreferencesPlaceholder()
      }
    }
    .frame(width: 520, height: 320)
  }
}

private struct PreferencesPlaceholder: View {
  var body: some View {
    ContentUnavailableView(
      "prefs.empty.title",
      systemImage: "hammer",
      description: Text("prefs.empty.message"))
  }
}
