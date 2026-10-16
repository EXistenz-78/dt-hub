import HubCore
import HubKit
import SwiftUI

/// The narrow rectangle at the right of the header, as tall as it: it opens the Results window. It pulses while a RUN
/// works and stays lit once the RUN is over with images the user has not seen, even with the window closed
/// (`ResultsAttention`).
struct ResultsEdgeButton: View {
  let generation: GenerationController
  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var attention: ResultsAttention
  @State private var pulse = false
  private let window = ResultsWindowMonitor.shared

  init(generation: GenerationController) {
    self.generation = generation
    _attention = State(initialValue: ResultsAttention(lastSeen: generation.session.results.first?.id))
  }

  private var newestID: UUID? { generation.session.results.first?.id }

  private var isBusy: Bool {
    generation.session.isRunning || generation.isPreparing || generation.isPipelineRunning
  }

  private var state: ResultsAttentionState {
    attention.state(isBusy: isBusy, newestResultID: newestID, windowVisible: window.isVisible)
  }

  var body: some View {
    let state = state
    Button {
      openWindow(id: ResultsWindow.id)
    } label: {
      Image(systemName: "chevron.right")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(state == .idle ? Color.primary : DS.accent)
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .dsGlass(RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous), tint: tint(for: state))
    .help(String(localized: "header.results.help"))
    .accessibilityLabel(String(localized: "header.results.help"))
    .accessibilityValue(accessibilityValue(for: state))
    .onChange(of: newestID) { attention.update(newestResultID: newestID, windowVisible: window.isVisible) }
    .onChange(of: window.isVisible) { attention.update(newestResultID: newestID, windowVisible: window.isVisible) }
    .onAppear { attention.update(newestResultID: newestID, windowVisible: window.isVisible) }
    .task(id: state == .working) { animate(working: state == .working) }
  }

  private func tint(for state: ResultsAttentionState) -> Color? {
    switch state {
    case .idle: nil
    case .working: DS.accent.opacity(pulse ? 0.55 : 0.15)
    case .unseen: DS.accent.opacity(0.75)
    }
  }

  private func accessibilityValue(for state: ResultsAttentionState) -> String {
    switch state {
    case .idle: ""
    case .working: String(localized: "header.results.working")
    case .unseen: String(localized: "header.results.unseen")
    }
  }

  /// A slow pulse while a RUN works; none with "Reduce motion" on (the button is then lit steadily).
  private func animate(working: Bool) {
    guard working else {
      withAnimation(.easeOut(duration: 0.2)) { pulse = false }
      return
    }
    if reduceMotion {
      pulse = true
    } else {
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
    }
  }
}
