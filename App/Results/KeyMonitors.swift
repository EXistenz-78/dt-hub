import AppKit
import HubCore
import SwiftUI

/// ⌫ and ⌘⌫ while the Results window is the key one and the strip has been clicked: calls `onDelete`
/// and takes the key. An AppKit monitor, because the key never reached a SwiftUI key handler on the
/// strip (⌘A, which goes through the menu, did).
struct DeleteKeyMonitor: NSViewRepresentable {
  var isActive: Bool
  var onDelete: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isActive = isActive
    context.coordinator.onDelete = onDelete
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.remove()
  }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var isActive = false
    var onDelete: () -> Void = {}
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        // Local monitors run on the main thread; the event never leaves it.
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, self.isActive, unsafeEvent.keyCode == 51,
            let window = self.view?.window, unsafeEvent.window === window, window.isKeyWindow
          else { return false }
          let flags = unsafeEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
          guard flags.isEmpty || flags == .command else { return false }
          self.onDelete()
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// ← and → while the Results window is the key one: calls `onStep(-1)` / `onStep(1)` and takes the key. Not with a
/// modifier, and not while a text is being edited. An AppKit monitor, like ⌫ above (SwiftUI never got the arrows here).
struct ArrowKeyMonitor: NSViewRepresentable {
  var onStep: (Int) -> Void
  /// ↓ (+1) and ↑ (−1), for a grid; without it those keys are left alone.
  var onVertical: ((Int) -> Void)?

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onStep = onStep
    context.coordinator.onVertical = onVertical
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var onStep: (Int) -> Void = { _ in }
    var onVertical: ((Int) -> Void)?
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, [123, 124].contains(unsafeEvent.keyCode) || (self.onVertical != nil && [125, 126].contains(unsafeEvent.keyCode)),
            let window = self.view?.window, unsafeEvent.window === window, window.isKeyWindow,
            !(window.firstResponder is NSText)
          else { return false }
          // The arrow keys always carry .numericPad and .function.
          let flags = unsafeEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
          guard flags.isEmpty else { return false }
          switch unsafeEvent.keyCode {
          case 123: self.onStep(-1)
          case 124: self.onStep(1)
          case 125: self.onVertical?(1)
          default: self.onVertical?(-1)
          }
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// A picture of the strip while it is dragged: its file (so the Control tab, the Finder and other apps take it).
struct DraggedResult: Identifiable, Transferable {
  let id: GeneratedImage.ID
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation { $0.url }
  }
}

/// A picture of the Explore grid while it is dragged: its file, under the id of the grid (the file's path).
struct DraggedGalleryFile: Identifiable, Transferable {
  let id: String
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation { $0.url }
  }
}

/// The mouse wheel over the strip scrolls it sideways: a wheel only turns up and down, so its movement is
/// taken by the horizontal scroll view under the pointer. A trackpad (two-finger swipe) already scrolls it.
struct WheelScrollsSideways: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.remove()
  }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, let view = self.view, let window = view.window, unsafeEvent.window === window,
            !unsafeEvent.hasPreciseScrollingDeltas, unsafeEvent.scrollingDeltaY != 0,
            unsafeEvent.scrollingDeltaX == 0
          else { return false }
          let point = view.convert(unsafeEvent.locationInWindow, from: nil)
          guard view.bounds.contains(point) else { return false }
          var found = window.contentView?.hitTest(window.contentView?.superview.map {
            $0.convert(unsafeEvent.locationInWindow, from: nil)
          } ?? unsafeEvent.locationInWindow)
          while let current = found, !(current is NSScrollView) { found = current.superview }
          guard let scroll = found as? NSScrollView, let document = scroll.documentView else { return false }
          let clip = scroll.contentView
          let maxX = max(0, document.frame.width - clip.bounds.width)
          guard maxX > 0 else { return false }
          // Wheel up (positive delta) goes back to the start of the strip.
          let step = unsafeEvent.scrollingDeltaY * 12
          clip.scroll(to: NSPoint(x: min(max(clip.bounds.origin.x - step, 0), maxX), y: clip.bounds.origin.y))
          scroll.reflectScrolledClipView(clip)
          return true
        }
        return taken ? nil : event
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
