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
  @Environment(CanvasWindowState.self) private var canvasWindow
  @Environment(\.openWindow) private var openWindow
  /// The tab itself holds focus, so Edit ▸ Paste (⌘V) reaches `onPasteCommand`.
  @FocusState private var hasFocus: Bool

  private var control: ControlStore { generation.control }

  var body: some View {
    // The window's height goes down to the cards, so the pictures can grow with it.
    GeometryReader { proxy in
      content
        .environment(\.controlViewportHeight, proxy.size.height)
        // Messages float over the cards: one that comes and goes must not move what is under the pointer.
        .overlay(alignment: .bottom) {
          VStack(spacing: DS.controlGap) { messageBar }
            .padding(.horizontal, DS.groupGap)
            .padding(.bottom, DS.controlGap)
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
          if canvasWindow.isOpen {
            CanvasDetachedNote()
          } else {
            CanvasStage(
              generation: generation, report: { message = $0 },
              detach: {
                canvasWindow.isOpen = true
                openWindow(id: CanvasWindow.id)
              })
          }
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
      bar(
        systemImage: "info.circle", text: ControlText.notice(notice), tint: .secondary,
        close: { control.dismissNotice() }
      ) {
        if control.canUndo { compactButton("control.undo") { control.undo() } }
      }
    }
    if let message {
      switch message {
      case .error(let text):
        bar(
          systemImage: "exclamationmark.triangle.fill", text: text, tint: DS.remove,
          close: { self.message = nil }
        ) {}
      case .adapted(let previous):
        bar(
          systemImage: "aspectratio", text: String(localized: "control.adapted"), tint: .secondary,
          close: { self.message = nil }
        ) {
          compactButton("control.undo") {
            generation.restoreDimensions(previous)
            self.message = nil
          }
        }
      }
    }
  }

  private func compactButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(.plain)
      .font(.caption.weight(.semibold))
      .foregroundStyle(DS.accent)
  }

  /// A small bar at the bottom: icon, text, optional action and an X that closes it.
  private func bar<Actions: View>(
    systemImage: String, text: String, tint: Color, close: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
  ) -> some View {
    HStack(spacing: DS.controlGap) {
      Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
      Text(verbatim: text).font(.caption).lineLimit(2)
      actions()
      Button(action: close) {
        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
          .frame(width: 18, height: 18).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "control.dismiss"))
      .help(String(localized: "control.dismiss"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: 420)
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
