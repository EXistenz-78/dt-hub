import AppKit
import Observation

/// Whether the Results window is on screen: open, not minimised and at least partly uncovered. The header's Results
/// button does not light for images that arrive while it is (design of 16 Oct 2026). One for the whole app.
@MainActor
@Observable
final class ResultsWindowMonitor {
  static let shared = ResultsWindowMonitor()

  private(set) var isVisible = false

  private init() {
    refresh()
    let names: [Notification.Name] = [
      NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification,
      NSWindow.didResignMainNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
      NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
    ]
    for name in names {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let closing = note.name == NSWindow.willCloseNotification ? note.object as? NSWindow : nil
        MainActor.assumeIsolated { self?.refresh(closing: closing) }
      }
    }
  }

  private func refresh(closing: NSWindow? = nil) {
    let title = String(localized: "results.title")
    let window = NSApp.windows.first { $0.title == title && $0 !== closing }
    let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
    if visible != isVisible { isVisible = visible }
  }
}
