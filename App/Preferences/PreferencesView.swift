import AppKit
import HubCore
import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7).
struct PreferencesView: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let languageModel: LanguageModelManager
  let download: LanguageModelDownloadController
  let plugins: PluginRegistry
  let projects: ProjectManager

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        DrawThingsPreferencesView(connection: connection)
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        LanguagePreferencesView(manager: languageModel, download: download, connection: connection)
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        OutputPreferencesView(controller: generation, projects: projects)
      }
      Tab("prefs.tab.plugins", systemImage: "puzzlepiece.extension") {
        PluginsPreferencesView(plugins: plugins)
      }
    }
    // Width fixed at 560 pt; the height can be changed.
    .frame(minWidth: 560, maxWidth: 560, minHeight: 420, maxHeight: .infinity)
    .background(ResizableHeightWindow(width: 560, minHeight: 420))
  }
}

/// The Settings window is not resizable by default: this lets its height be changed (the width stays as it is).
private struct ResizableHeightWindow: NSViewRepresentable {
  let width: CGFloat
  let minHeight: CGFloat

  func makeNSView(context: Context) -> NSView { Configuring(width: width, minHeight: minHeight) }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class Configuring: NSView {
    let width: CGFloat
    let minHeight: CGFloat
    init(width: CGFloat, minHeight: CGFloat) {
      self.width = width
      self.minHeight = minHeight
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    private var observation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window else { return }
      apply(to: window)
      // SwiftUI sets the window's style again when the tab (and so the content) changes: it is put right again.
      observation = window.observe(\.styleMask, options: [.new]) { [weak self] window, _ in
        DispatchQueue.main.async { self?.apply(to: window) }
      }
      DispatchQueue.main.async { [weak self] in self?.apply(to: window) }
    }

    private func apply(to window: NSWindow) {
      if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
      window.contentMinSize = NSSize(width: width, height: minHeight)
      window.contentMaxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }
  }
}
