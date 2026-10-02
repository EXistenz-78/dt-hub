import HubCore
import HubKit
import SwiftUI

/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt: the start image,
/// the Moodboard and the canvas with the inpaint mask. Everything is on one screen, so there is no
/// summary strip; the warnings are in the cards they are about.
struct ControlTabView: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  @State private var message: ControlMessage?
  /// The tab itself holds focus, so Edit ▸ Paste (⌘V) reaches `onPasteCommand`.
  @FocusState private var hasFocus: Bool

  private var control: ControlStore { generation.control }

  var body: some View {
    // The window's height goes down to the cards, so the pictures can grow with it.
    GeometryReader { proxy in
      content
        .environment(\.controlViewportHeight, proxy.size.height)
        // Messages float over the cards: one that comes and goes must not move what is under the pointer.
        .overlay(alignment: .top) {
          VStack(spacing: DS.controlGap) { messageBar }
            .padding(.horizontal, DS.groupGap)
            .padding(.top, DS.controlGap)
            .animation(.easeInOut(duration: 0.15), value: control.notice)
            .animation(.easeInOut(duration: 0.15), value: message)
        }
    }
  }

  private var content: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        DSCardRow {
          VStack(spacing: DS.groupGap) {
            ImageCard(generation: generation, connection: connection) { message = $0 }
            MoodboardCard(generation: generation, connection: connection) { message = $0 }
          }
          CanvasStage(generation: generation) { message = $0 }
        }
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
    .focusable()
    .focusEffectDisabled()
    .focused($hasFocus)
    .onAppear { hasFocus = true }
    .simultaneousGesture(TapGesture().onEnded { hasFocus = true })
    .onPasteCommand(of: [.fileURL, .image]) { providers in
      Task { if let text = await ControlImport.take(providers: providers, into: control) { message = .error(text) } }
    }
    .background { undoShortcuts }
    .task(id: control.notice) {
      guard control.notice != nil else { return }
      try? await Task.sleep(for: .seconds(8))
      control.dismissNotice()
    }
  }

  /// ⌘Z and ⇧⌘Z while the tab is on screen; a text field in focus keeps its own undo.
  private var undoShortcuts: some View {
    HStack {
      Button { control.undo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: .command).disabled(!control.canUndo)
      Button { control.redo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!control.canRedo)
    }
    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
  }

  @ViewBuilder private var messageBar: some View {
    if let notice = control.notice {
      bar(systemImage: "info.circle", text: ControlText.notice(notice), tint: .secondary) {
        if control.canUndo { Button("control.undo") { control.undo() }.buttonStyle(DSPillButtonStyle()) }
      }
    }
    if let message {
      switch message {
      case .error(let text):
        bar(systemImage: "exclamationmark.triangle.fill", text: text, tint: DS.remove) {
          Button("control.dismiss") { self.message = nil }.buttonStyle(DSPillButtonStyle())
        }
      case .adapted(let previous):
        bar(systemImage: "aspectratio", text: String(localized: "control.adapted"), tint: .secondary) {
          Button("control.undo") {
            generation.restoreDimensions(previous)
            self.message = nil
          }
          .buttonStyle(DSPillButtonStyle())
        }
      }
    }
  }

  private func bar<Actions: View>(
    systemImage: String, text: String, tint: Color, @ViewBuilder actions: () -> Actions
  ) -> some View {
    HStack(spacing: DS.controlGap) {
      Image(systemName: systemImage).foregroundStyle(tint)
      Text(verbatim: text).font(.callout)
      Spacer(minLength: 0)
      actions()
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity)
    .dsPanel()
    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
  }
}

private struct ControlViewportHeightKey: EnvironmentKey {
  static let defaultValue: Double = 700
}

extension EnvironmentValues {
  /// The height of the Control tab's window.
  var controlViewportHeight: Double {
    get { self[ControlViewportHeightKey.self] }
    set { self[ControlViewportHeightKey.self] = newValue }
  }
}
