import HubCore
import SwiftUI

/// Run (⌘↩) and Stop (⌘.) in the Generation menu: menu shortcuts work whichever DT Hub
/// window is in front, the Results window included.
struct GenerationCommands: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button {
      if generation.run(with: connection) { openWindow(id: ResultsWindow.id) }
    } label: {
      Text("header.run")
    }
    .keyboardShortcut(.return, modifiers: .command)
    .disabled(!generation.canRun(with: connection))

    Button {
      generation.session.cancel()
    } label: {
      Text("header.stop")
    }
    .keyboardShortcut(".", modifiers: .command)
    .disabled(!generation.session.isRunning)
  }
}
