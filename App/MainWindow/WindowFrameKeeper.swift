import AppKit
import SwiftUI

/// Remembers the size and position of the window it is in, under a key of its own, and puts the window back there at
/// the next launch. SwiftUI's own memory is named after the type of the window's content, so it is lost whenever that
/// type changes, and the window then opens as big as the screen.
struct WindowFrameKeeper: NSViewRepresentable {
  let key: String
  let minSize: CGSize

  func makeNSView(context: Context) -> NSView { Keeper(key: key, minSize: minSize) }
  func updateNSView(_ nsView: NSView, context: Context) {}

  static let mainKey = "mainWindow.frame"
  static let mainMinSize = CGSize(width: 900, height: 640)

  /// SwiftUI restores the main window from its own entry in the defaults (named after the type of the content) and,
  /// when macOS had tiled the window (snapped to an edge), opens it as big as the screen first. The entry is rewritten
  /// with the frame this app kept, without the tiling, before the window is made: it then opens in place at once.
  /// Entries that do not exist yet are not made (the keeper puts the window right after it appears).
  static func preseedSystemFrame(key: String, minSize: CGSize, defaults: UserDefaults = .standard) {
    guard
      let frame = savedFrame(
        defaults.string(forKey: key), minSize: minSize, screens: NSScreen.screens.map(\.visibleFrame)),
      let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
    else { return }
    let area = screen.visibleFrame
    func whole(_ value: CGFloat) -> Int { Int(value.rounded()) }
    let text =
      "\(whole(frame.minX)) \(whole(frame.minY)) \(whole(frame.width)) \(whole(frame.height)) "
      + "\(whole(area.minX)) \(whole(area.minY)) \(whole(area.width)) \(whole(area.height)) "
    for name in defaults.dictionaryRepresentation().keys
    where name.hasPrefix("NSWindow Frame ") && name.contains("MainWindowView") {
      defaults.set(text, forKey: name)
    }
  }

  /// The frame as it was saved, if it still fits a screen that is connected.
  static func savedFrame(_ text: String?, minSize: CGSize, screens: [CGRect]) -> CGRect? {
    guard let text else { return nil }
    let frame = NSRectFromString(text)
    guard frame.width >= minSize.width, frame.height >= minSize.height,
      screens.contains(where: { $0.intersection(frame).width >= 100 && $0.intersection(frame).height >= 100 })
    else { return nil }
    return frame
  }

  private final class Keeper: NSView {
    let key: String
    let minSize: CGSize
    private var tokens: [NSObjectProtocol] = []
    private var startedAt = Date()

    init(key: String, minSize: CGSize) {
      self.key = key
      self.minSize = minSize
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window, tokens.isEmpty else { return }
      startedAt = Date()
      let saved = Self.saved(key: key, minSize: minSize)
      // SwiftUI sizes the window after this view is in it: the saved frame is put back a few times, and nothing is
      // saved until the window has settled, so the size SwiftUI picks first never replaces the one the user chose.
      if let saved {
        for delay in [0.0, 0.05, 0.4] {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            window.setFrame(saved, display: true)
          }
        }
      }
      let center = NotificationCenter.default
      for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
        tokens.append(
          center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.save(window) }
          })
      }
      tokens.append(
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self, weak window] _ in
          MainActor.assumeIsolated { if let window { self?.save(window) } }
        })
    }

    private static func saved(key: String, minSize: CGSize) -> CGRect? {
      WindowFrameKeeper.savedFrame(
        UserDefaults.standard.string(forKey: key), minSize: minSize, screens: NSScreen.screens.map(\.visibleFrame))
    }

    private func save(_ window: NSWindow) {
      guard Date().timeIntervalSince(startedAt) > 1.5, !window.styleMask.contains(.fullScreen) else { return }
      UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
    }
  }
}
