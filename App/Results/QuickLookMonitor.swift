import AppKit
import HubCore
@preconcurrency import Quartz
import SwiftUI

/// The space bar over the Explore grid: shows the chosen picture large in the Quick Look panel, and hides it again.
/// Esc hides it too. The panel does not take the keyboard, so the arrow keys keep moving the choice and the panel
/// follows. An AppKit monitor, like the arrow keys (SwiftUI never got these keys here).
///
/// `url` is the file to show (nil: nothing, or more than one picture selected); `isEnabled` is false while the search
/// box is being typed in.
struct QuickLookMonitor: NSViewRepresentable {
  var url: URL?
  var isEnabled: Bool

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isEnabled = isEnabled
    context.coordinator.update(url: url)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  /// The file Quick Look should show for a gallery picture: the clip of a video, else the picture.
  static func previewURL(for picture: URL) -> URL {
    let clip = PNGImageStore.videoURL(forPoster: picture)
    return FileManager.default.fileExists(atPath: clip.path) ? clip : picture
  }

  @MainActor
  final class Coordinator: NSObject, QLPreviewPanelDataSource {
    weak var view: NSView?
    var isEnabled = false
    private var url: URL?
    private var monitor: Any?

    private var panel: QLPreviewPanel? { QLPreviewPanel.shared() }
    private var isShowing: Bool { panel.map { $0.isVisible && $0.dataSource === self } ?? false }

    func update(url: URL?) {
      self.url = url
      guard isShowing, let panel else { return }
      if url == nil { panel.orderOut(nil) } else { panel.reloadData() }
    }

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        nonisolated(unsafe) let unsafeEvent = event
        let taken = MainActor.assumeIsolated { () -> Bool in
          guard let self, let window = self.view?.window, unsafeEvent.window === window, window.isKeyWindow,
            !(window.firstResponder is NSText),
            unsafeEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
          else { return false }
          switch unsafeEvent.keyCode {
          case 49 where self.isEnabled:
            self.toggle()
            return self.url != nil || self.isShowing
          case 53 where self.isShowing:
            self.panel?.orderOut(nil)
            return true
          default:
            return false
          }
        }
        return taken ? nil : event
      }
    }

    private func toggle() {
      guard let panel else { return }
      if isShowing {
        panel.orderOut(nil)
      } else if url != nil {
        panel.dataSource = self
        panel.reloadData()
        panel.orderFront(nil)
      }
    }

    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      if isShowing { panel?.orderOut(nil) }
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
      url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
      url.map { $0 as NSURL }
    }
  }
}
