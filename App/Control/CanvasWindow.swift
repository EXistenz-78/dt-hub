import HubCore
import HubKit
import SwiftUI

/// The Canvas card in a window of its own (opened by the button in the card's corner). While the window
/// is open the card is not in the Control tab: a note with a button to bring it back stands there.
enum CanvasWindow {
  static let id = "canvas"
}

/// Whether the canvas window is open. The window sets it when it appears and clears it when it goes.
@MainActor
@Observable
final class CanvasWindowState {
  var isOpen = false
}

/// The content of the canvas window: the same card, always open, over the Control tab's store.
struct CanvasWindowView: View {
  let generation: GenerationController
  @Environment(CanvasWindowState.self) private var state
  @State private var message: String?

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        CanvasStage(generation: generation, report: report, isInOwnWindow: true)
          .environment(\.controlViewportHeight, proxy.size.height)
          .padding(20)
      }
      .overlay(alignment: .top) {
        if let message {
          HStack(spacing: DS.controlGap) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.remove)
            Text(verbatim: message).font(.callout)
            Spacer(minLength: 0)
            Button("control.dismiss") { self.message = nil }.buttonStyle(DSPillButtonStyle())
          }
          .padding(DS.panelPadding)
          .dsPanel()
          .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
          .padding(20)
        }
      }
    }
    .frame(minWidth: 480, idealWidth: 720, minHeight: 520, idealHeight: 780)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
    // ⌘Z and ⇧⌘Z undo the strokes of the tab's history, as in the tab.
    .background { undoShortcuts }
    .onAppear { state.isOpen = true }
    .onDisappear { state.isOpen = false }
  }

  private func report(_ message: ControlMessage) {
    if case .error(let text) = message { self.message = text }
  }

  private var undoShortcuts: some View {
    HStack {
      Button { generation.control.undo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: .command).disabled(!generation.control.canUndo)
      Button { generation.control.redo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!generation.control.canRedo)
    }
    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
  }
}

/// What the Control tab shows where the Canvas card was, while its window is open.
struct CanvasDetachedNote: View {
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    VStack(spacing: DS.controlGap) {
      Image(systemName: "rectangle.dashed").font(.system(size: 22)).foregroundStyle(.secondary)
      Text("control.stage.detached").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("control.stage.reattach") { dismissWindow(id: CanvasWindow.id) }
        .buttonStyle(DSPillButtonStyle())
    }
    .padding(DS.panelPadding * 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .dsPanel()
  }
}
