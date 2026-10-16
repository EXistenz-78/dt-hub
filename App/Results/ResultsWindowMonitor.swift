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
    // The observers live as long as the app does (this is a singleton): their tokens are not kept.
    for name in names {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let closing = note.name == NSWindow.willCloseNotification ? note.object as? NSWindow : nil
        MainActor.assumeIsolated { self?.refresh(closing: closing) }
      }
    }
  }

  /// The Results window is found by its scene identifier (SwiftUI gives the window "results…") or, failing that, by its
  /// title; every match counts, because SwiftUI can keep a closed window of the same scene in `NSApp.windows`.
  private func refresh(closing: NSWindow? = nil) {
    let title = String(localized: "results.title")
    let visible = NSApp.windows.contains { window in
      window !== closing
        && (window.identifier?.rawValue.hasPrefix(ResultsWindow.id) == true || window.title == title)
        && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
    if visible != isVisible { isVisible = visible }
  }
}
