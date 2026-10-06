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
      generation.stop()
    } label: {
      Text("header.stop")
    }
    .keyboardShortcut(".", modifiers: .command)
    .disabled(!generation.session.isRunning && !generation.isPreparing)

    Divider()

    // Brings the window forward when it is open already.
    Button {
      openWindow(id: ResultsWindow.id)
    } label: {
      Text("menu.results")
    }
    .keyboardShortcut("r", modifiers: .command)
  }
}

/// ⌘⌥← and ⌘⌥→ step through the tabs. Menu commands, not bare arrow keys: those belong to the text
/// fields, the sliders and the lists.
struct TabCommands: View {
  let workspace: WorkspaceState

  var body: some View {
    Button {
      workspace.selectPrevious()
    } label: {
      Text("menu.tabs.previous")
    }
    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

    Button {
      workspace.selectNext()
    } label: {
      Text("menu.tabs.next")
    }
    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
  }
}
