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
