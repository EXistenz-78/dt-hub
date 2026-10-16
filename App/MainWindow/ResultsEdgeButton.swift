import HubCore
import HubKit
import SwiftUI

/// The narrow rectangle at the right of the header, as tall as it: it opens the Results window. It pulses while a RUN
/// works and stays lit once the RUN is over with images the user has not seen, even with the window closed
/// (`ResultsAttention`).
struct ResultsEdgeButton: View {
  let generation: GenerationController
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var attention: ResultsAttention
  private let window = ResultsWindowMonitor.shared

  init(generation: GenerationController) {
    self.generation = generation
    _attention = State(initialValue: ResultsAttention())
  }

  /// The newest image this session made (the ones read back from disk do not count).
  private var newestDate: Date? { ResultsAttention.newestDate(in: generation.session.results) }

  private var isBusy: Bool {
    generation.session.isRunning || generation.isPreparing || generation.isPipelineRunning
  }

  private var state: ResultsAttentionState {
    attention.state(isBusy: isBusy, newestDate: newestDate, windowVisible: window.isVisible)
  }

  var body: some View {
    // One branch for each state: a state change replaces the view, so nothing of a pulse is left behind (a repeating
    // `withAnimation` stayed attached to the view and kept it pulsing after the RUN).
    Group {
      switch state {
      case .working where !reduceMotion:
        TimelineView(.animation) { context in button(tint: pulseTint(at: context.date), state: .working) }
      case .working:
        button(tint: DS.accent.opacity(0.55), state: .working)
      case .unseen:
        button(tint: DS.accent.opacity(0.75), state: .unseen)
      case .idle:
        button(tint: nil, state: .idle)
      }
    }
    .onChange(of: newestDate) { attention.update(newestDate: newestDate, windowVisible: window.isVisible) }
    .onChange(of: window.isVisible) { attention.update(newestDate: newestDate, windowVisible: window.isVisible) }
    .onAppear { attention.update(newestDate: newestDate, windowVisible: window.isVisible) }
  }

  /// A click opens the Results window, or closes it when it is on screen.
  private func button(tint: Color?, state: ResultsAttentionState) -> some View {
    Button {
      if window.isVisible {
        dismissWindow(id: ResultsWindow.id)
      } else {
        openWindow(id: ResultsWindow.id)
      }
    } label: {
      Image(systemName: "chevron.right")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(state == .idle ? Color.primary : DS.accent)
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .dsGlass(RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous), tint: tint)
    .help(String(localized: "header.results.help"))
    .accessibilityLabel(String(localized: "header.results.help"))
    .accessibilityValue(accessibilityValue(for: state))
  }

  /// The tint swings slowly (a period of 1.8 s) while a RUN works, from the time itself.
  private func pulseTint(at date: Date) -> Color {
    let phase = (sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 1.8) + 1) / 2
    return DS.accent.opacity(0.15 + 0.4 * phase)
  }

  private func accessibilityValue(for state: ResultsAttentionState) -> String {
    switch state {
    case .idle: ""
    case .working: String(localized: "header.results.working")
    case .unseen: String(localized: "header.results.unseen")
    }
  }
}
